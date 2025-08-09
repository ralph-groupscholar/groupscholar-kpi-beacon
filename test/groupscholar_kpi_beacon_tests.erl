-module(groupscholar_kpi_beacon_tests).

-include_lib("eunit/include/eunit.hrl").

parse_date_valid_test() ->
    ?assertMatch({ok, {date, {2026, 2, 2}}}, groupscholar_kpi_beacon:parse_date("2026-02-02")).

parse_date_invalid_test() ->
    ?assertMatch({error, _}, groupscholar_kpi_beacon:parse_date("2026/02/02")).

parse_number_int_test() ->
    ?assertEqual({ok, 42}, groupscholar_kpi_beacon:parse_number("42")).

parse_number_float_test() ->
    ?assertMatch({ok, 42.5}, groupscholar_kpi_beacon:parse_number("42.5")).

parse_integer_invalid_test() ->
    ?assertMatch({error, _}, groupscholar_kpi_beacon:parse_integer("4.2")).

parse_args_help_test() ->
    {ok, Command, Options} = groupscholar_kpi_beacon:parse_args(["list", "--help"]),
    ?assertEqual("help", Command),
    ?assertEqual("true", maps:get("help", Options)).

parse_args_log_test() ->
    {ok, Command, Options} = groupscholar_kpi_beacon:parse_args([
        "log",
        "--week", "2026-02-02",
        "--metric", "applications_reviewed",
        "--value", "142",
        "--unit", "applications"
    ]),
    ?assertEqual("log", Command),
    ?assertEqual("2026-02-02", maps:get("week", Options)),
    ?assertEqual("applications_reviewed", maps:get("metric", Options)).

parse_args_trend_test() ->
    {ok, Command, Options} = groupscholar_kpi_beacon:parse_args([
        "trend",
        "--metric", "scholar_engagement",
        "--limit", "6",
        "--unit", "points"
    ]),
    ?assertEqual("trend", Command),
    ?assertEqual("scholar_engagement", maps:get("metric", Options)),
    ?assertEqual("6", maps:get("limit", Options)),
    ?assertEqual("points", maps:get("unit", Options)).
