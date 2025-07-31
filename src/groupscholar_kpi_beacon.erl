-module(groupscholar_kpi_beacon).

%% API exports
-export([main/1]).

%% Test exports
-export([parse_args/1, parse_date/1, parse_number/1, parse_integer/1, valid_date_string/1]).

-define(DEFAULT_DB_HOST, "db-acupinir.groupscholar.com").
-define(DEFAULT_DB_PORT, 23947).
-define(DEFAULT_DB_NAME, "postgres").
-define(DEFAULT_DB_USER, "ralph").
-define(SCHEMA, "kpi_beacon").

%%====================================================================
%% API functions
%%====================================================================

%% escript Entry point
main(Args) ->
    case parse_args(Args) of
        {ok, Command, Options} ->
            case run_command(Command, Options) of
                ok ->
                    erlang:halt(0);
                {error, Message} ->
                    io:format("~s~n", [Message]),
                    erlang:halt(1)
            end;
        {error, Message} ->
            io:format("~s~n", [Message]),
            io:format("~s~n", [usage()]),
            erlang:halt(1)
    end.

%%====================================================================
%% Internal functions
%%====================================================================

run_command("help", _Options) ->
    io:format("~s~n", [usage()]),
    ok;
run_command("init", _Options) ->
    with_connection(fun(Connection) ->
        run_sql_file(Connection, "db/schema.sql")
    end);
run_command("seed", _Options) ->
    with_connection(fun(Connection) ->
        run_sql_file(Connection, "db/seed.sql")
    end);
run_command("log", Options) ->
    Required = ["week", "metric", "value", "unit"],
    case ensure_required(Required, Options) of
        ok ->
            insert_kpi_entry(Options);
        {error, Message} ->
            {error, Message}
    end;
run_command("list", Options) ->
    list_entries(Options);
run_command("summary", Options) ->
    Required = ["week"],
    case ensure_required(Required, Options) of
        ok ->
            summarize_week(Options);
        {error, Message} ->
            {error, Message}
    end;
run_command(Unknown, _Options) ->
    {error, io_lib:format("Unknown command: ~s", [Unknown])}.

parse_args([]) ->
    {error, "Missing command."};
parse_args([Command | Rest]) ->
    case parse_flags(Rest, #{}, []) of
        {ok, Options} ->
            CommandName = normalize_command(Command, Options),
            {ok, CommandName, Options};
        {error, Message} ->
            {error, Message}
    end.

parse_flags([], Options, []) ->
    {ok, Options};
parse_flags([], _Options, Errors) ->
    {error, string:join(lists:reverse(Errors), "\n")};
parse_flags(["--help" | Rest], Options, Errors) ->
    parse_flags(Rest, maps:put("help", "true", Options), Errors);
parse_flags([Flag, Value | Rest], Options, Errors) ->
    case string:prefix(Flag, "--") of
        nomatch ->
            parse_flags(Rest, Options, [io_lib:format("Unexpected argument: ~s", [Flag]) | Errors]);
        _ ->
            Key = string:trim(Flag, leading, "-"),
            parse_flags(Rest, maps:put(Key, Value, Options), Errors)
    end;
parse_flags([Flag], Options, Errors) ->
    parse_flags([], Options, [io_lib:format("Missing value for ~s", [Flag]) | Errors]).

normalize_command(Command, Options) ->
    case maps:get("help", Options, "false") of
        "true" -> "help";
        _ -> Command
    end.

usage() ->
    string:join([
        "gs-kpi-beacon <command> [options]",
        "",
        "Commands:",
        "  init                           Create schema + table in Postgres",
        "  seed                           Insert seed KPI data",
        "  log --week YYYY-MM-DD --metric NAME --value NUM --unit UNIT [--program NAME] [--source NAME] [--notes TEXT]",
        "  list [--limit N] [--week YYYY-MM-DD]",
        "  summary --week YYYY-MM-DD",
        "  help",
        "",
        "Environment:",
        "  GS_KPI_BEACON_DB_HOST (default: db-acupinir.groupscholar.com)",
        "  GS_KPI_BEACON_DB_PORT (default: 23947)",
        "  GS_KPI_BEACON_DB_NAME (default: postgres)",
        "  GS_KPI_BEACON_DB_USER (default: ralph)",
        "  GS_KPI_BEACON_DB_PASSWORD (required)",
        ""
    ], "\n").

ensure_required(Keys, Options) ->
    Missing = [Key || Key <- Keys, maps:is_key(Key, Options) =:= false],
    case Missing of
        [] -> ok;
        _ -> {error, io_lib:format("Missing required options: ~s", [string:join(Missing, ", ")])}
    end.

insert_kpi_entry(Options) ->
    Week = maps:get("week", Options),
    Metric = maps:get("metric", Options),
    ValueStr = maps:get("value", Options),
    Unit = maps:get("unit", Options),
    Program = maps:get("program", Options, null),
    Source = maps:get("source", Options, null),
    Notes = maps:get("notes", Options, null),
    case {parse_date(Week), parse_number(ValueStr)} of
        {{ok, Date}, {ok, Value}} ->
            with_connection(fun(Connection) ->
                Query = "INSERT INTO " ++ ?SCHEMA ++ ".kpi_entries "
                    "(week_start, metric, value, unit, program, source, notes) "
                    "VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
                case epgsql:equery(Connection, Query, [Date, Metric, Value, Unit, Program, Source, Notes]) of
                    {ok, _Columns, [{Id}]} ->
                        io:format("Logged KPI entry with id ~p~n", [Id]),
                        ok;
                    {error, Error} ->
                        {error, io_lib:format("Insert failed: ~p", [Error])}
                end
            end);
        {{error, DateError}, _} ->
            {error, DateError};
        {_, {error, ValueError}} ->
            {error, ValueError}
    end.

list_entries(Options) ->
    Limit = maps:get("limit", Options, "20"),
    WeekFilter = maps:get("week", Options, null),
    case parse_integer(Limit) of
        {ok, LimitValue} ->
            case list_filter(WeekFilter) of
                {ok, WhereClause, Params} ->
                    with_connection(fun(Connection) ->
                        Query = "SELECT id, week_start, metric, value, unit, program, source, notes, created_at "
                            "FROM " ++ ?SCHEMA ++ ".kpi_entries " ++ WhereClause ++ " "
                            "ORDER BY week_start DESC, created_at DESC "
                            "LIMIT $" ++ integer_to_list(length(Params) + 1),
                        case epgsql:equery(Connection, Query, Params ++ [LimitValue]) of
                            {ok, _Columns, Rows} ->
                                print_rows(Rows),
                                ok;
                            {error, Error} ->
                                {error, io_lib:format("List failed: ~p", [Error])}
                        end
                    end);
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.

summarize_week(Options) ->
    Week = maps:get("week", Options),
    case parse_date(Week) of
        {ok, Date} ->
            with_connection(fun(Connection) ->
                Query = "SELECT metric, unit, sum(value) "
                    "FROM " ++ ?SCHEMA ++ ".kpi_entries "
                    "WHERE week_start = $1 "
                    "GROUP BY metric, unit "
                    "ORDER BY metric",
                case epgsql:equery(Connection, Query, [Date]) of
                    {ok, _Columns, Rows} ->
                        print_summary(Rows),
                        ok;
                    {error, Error} ->
                        {error, io_lib:format("Summary failed: ~p", [Error])}
                end
            end);
        {error, Error} ->
            {error, Error}
    end.

list_filter(null) ->
    {ok, "", []};
list_filter(Week) ->
    case parse_date(Week) of
        {ok, Date} ->
            {ok, "WHERE week_start = $1", [Date]};
        {error, Error} ->
            {error, Error}
    end.

print_rows([]) ->
    io:format("No KPI entries found.~n");
print_rows(Rows) ->
    lists:foreach(fun(Row) ->
        {Id, WeekStart, Metric, Value, Unit, Program, Source, Notes, CreatedAt} = Row,
        io:format(
            "#~p | ~p | ~s = ~p ~s | program=~p | source=~p | notes=~p | created_at=~p~n",
            [Id, WeekStart, Metric, Value, Unit, Program, Source, Notes, CreatedAt]
        )
    end, Rows).

print_summary([]) ->
    io:format("No KPI entries for that week.~n");
print_summary(Rows) ->
    lists:foreach(fun(Row) ->
        {Metric, Unit, SumValue} = Row,
        io:format("~s: ~p ~s~n", [Metric, SumValue, Unit])
    end, Rows).

run_sql_file(Connection, Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            Statements = split_sql(binary_to_list(Bin)),
            run_statements(Connection, Statements);
        {error, Reason} ->
            {error, io_lib:format("Failed to read ~s: ~p", [Path, Reason])}
    end.

split_sql(Sql) ->
    [Statement || Statement <- string:tokens(Sql, ";"), string:trim(Statement) =/= ""].

run_statements(_Connection, []) ->
    ok;
run_statements(Connection, [Statement | Rest]) ->
    case epgsql:squery(Connection, string:trim(Statement)) of
        {ok, _Count} ->
            run_statements(Connection, Rest);
        {ok, _Cols, _Rows} ->
            run_statements(Connection, Rest);
        {error, Error} ->
            {error, io_lib:format("SQL failed: ~p", [Error])}
    end.

with_connection(Fun) ->
    case connect() of
        {ok, Connection} ->
            try
                Fun(Connection)
            after
                epgsql:close(Connection)
            end;
        {error, Reason} ->
            {error, Reason}
    end.

connect() ->
    case getenv_required("GS_KPI_BEACON_DB_PASSWORD") of
        {ok, Password} ->
            Host = getenv("GS_KPI_BEACON_DB_HOST", ?DEFAULT_DB_HOST),
            Port = getenv_int("GS_KPI_BEACON_DB_PORT", ?DEFAULT_DB_PORT),
            User = getenv("GS_KPI_BEACON_DB_USER", ?DEFAULT_DB_USER),
            Database = getenv("GS_KPI_BEACON_DB_NAME", ?DEFAULT_DB_NAME),
            epgsql:connect(Host, User, Password, #{database => Database, port => Port});
        {error, Message} ->
            {error, Message}
    end.

getenv(Key, Default) ->
    case os:getenv(Key) of
        false -> Default;
        Value -> Value
    end.

getenv_required(Key) ->
    case os:getenv(Key) of
        false ->
            {error, io_lib:format("Missing required env var: ~s", [Key])};
        Value -> {ok, Value}
    end.

getenv_int(Key, Default) ->
    case os:getenv(Key) of
        false -> Default;
        Value ->
            case string:to_integer(Value) of
                {IntValue, _} -> IntValue;
                _ -> Default
            end
    end.

valid_date_string(DateString) when is_list(DateString) ->
    case DateString of
        [Y1,Y2,Y3,Y4,$-,M1,M2,$-,D1,D2] ->
            lists:all(fun is_digit/1, [Y1,Y2,Y3,Y4,M1,M2,D1,D2]);
        _ ->
            false
    end;
valid_date_string(_) ->
    false.

parse_date(DateString) ->
    case valid_date_string(DateString) of
        true ->
            [Y1,Y2,Y3,Y4,$-,M1,M2,$-,D1,D2] = DateString,
            {ok, {date, {list_to_integer([Y1,Y2,Y3,Y4]), list_to_integer([M1,M2]), list_to_integer([D1,D2])}}};
        false ->
            {error, io_lib:format("Invalid date format: ~s (expected YYYY-MM-DD)", [DateString])}
    end.

parse_number(ValueString) when is_list(ValueString) ->
    case string:to_integer(ValueString) of
        {IntValue, ""} -> {ok, IntValue};
        _ ->
            case string:to_float(ValueString) of
                {FloatValue, _} -> {ok, FloatValue};
                _ -> {error, io_lib:format("Invalid number: ~s", [ValueString])}
            end
    end;
parse_number(_) ->
    {error, "Invalid number input"}.

parse_integer(ValueString) when is_list(ValueString) ->
    case string:to_integer(ValueString) of
        {IntValue, ""} -> {ok, IntValue};
        _ -> {error, io_lib:format("Invalid integer: ~s", [ValueString])}
    end;
parse_integer(_) ->
    {error, "Invalid integer input"}.

is_digit(Char) when Char >= $0, Char =< $9 -> true;
is_digit(_) -> false.
