-module(prometheus_histogram_tests).

-include_lib("eunit/include/eunit.hrl").

prometheus_format_test_() ->
  {foreach,
   fun prometheus_eunit_common:start/0,
   fun prometheus_eunit_common:stop/1,
   [fun test_registration/1,
    fun test_errors/1,
    fun test_buckets/1,
    fun test_int/1,
    fun test_double/1,
    fun test_observe_duration/1]}.

test_registration(_)->
  Name = request_duration,
  Spec = [{name, request_duration}, {buckets, [100, 300, 500, 750, 1000]}, {help, "Track requests duration"}],
  [?_assertEqual(true,
                 prometheus_counter:declare(Spec)),
   ?_assertEqual(false,
                 prometheus_counter:declare(Spec)),
   ?_assertError({mf_already_exists, {default, Name}, "Consider using declare instead."},
                 prometheus_counter:new(Spec))].

test_errors(_) ->
  prometheus_histogram:new([{name, request_duration}, {buckets, [100, 300, 500, 750, 1000]}, {help, "Track requests duration"}]),
  [%% basic name/labels/help validations test, lets hope new is using extract_common_params
   ?_assertError({invalid_metric_name, 12, "metric name is not a string"}, prometheus_histogram:new([{name, 12}, {help, ""}])),
   ?_assertError({invalid_metric_labels, 12, "not list"}, prometheus_histogram:new([{name, "qwe"}, {labels, 12}, {help, ""}])),
   ?_assertError({invalid_metric_label_name, "le", "histogram cannot have a label named \"le\""},
                 prometheus_histogram:new([{name, "qwe"}, {labels, ["qwe", "le"]}, {help, ""}])),
   ?_assertError({invalid_metric_help, 12, "metric help is not a string"}, prometheus_histogram:new([{name, "qwe"}, {help, 12}])),
   %% histogram specific errors
   ?_assertError({histogram_no_buckets, []}, prometheus_histogram:new([{name, "qwe"}, {help, ""}, {buckets, []}])),
   ?_assertError({histogram_invalid_buckets, 1}, prometheus_histogram:new([{name, "qwe"}, {help, ""}, {buckets, 1}])),
   ?_assertError({histogram_invalid_bound, "qwe"}, prometheus_histogram:new([{name, "qwe"}, {help, ""}, {buckets, ["qwe"]}])),
   ?_assertError({histogram_invalid_buckets, [1, 3, 2], "Buckets not sorted"}, prometheus_histogram:new([{name, "qwe"}, {help, ""}, {buckets, [1, 3, 2]}])),
   ?_assertError({invalid_value, 1.5, "observe accepts only integers"}, prometheus_histogram:observe(request_duration, 1.5)),
   ?_assertError({invalid_value, "qwe", "observe accepts only integers"}, prometheus_histogram:observe(request_duration, "qwe")),
   ?_assertError({invalid_value, "qwe", "dobserve accepts only numbers"}, prometheus_histogram:dobserve(request_duration, "qwe"))
  ].

test_buckets(_) ->
  prometheus_histogram:new([{name, "default_buckets"}, {help, ""}]),
  DefaultBuckets = prometheus_histogram:buckets("default_buckets"),
  prometheus_histogram:new([{name, http_request_duration_milliseconds},
                            {labels, [method]},
                            {buckets, [100, 300, 500, 750, 1000]},
                            {help, "Http Request execution time"}]),

  prometheus_histogram:new([{name, "linear_buckets"}, {help, ""}, {buckets, {linear, -15, 5, 6}}]),
  LinearBuckets = prometheus_histogram:buckets("linear_buckets"),

  prometheus_histogram:declare([{name, "exp_buckets"}, {help, ""}, {buckets, {exponential, 100, 1.2, 3}}]),
  ExpBuckets = prometheus_histogram:buckets("exp_buckets"),

  CustomBuckets = prometheus_histogram:buckets(http_request_duration_milliseconds, [method]),
  [?_assertEqual(prometheus_histogram:default_buckets() ++ [infinity], DefaultBuckets),
   ?_assertEqual([100, 300, 500, 750, 1000, infinity], CustomBuckets),
   ?_assertEqual([-15, -10, -5, 0, 5, 10], prometheus_histogram:linear_buckets(-15, 5, 6)),
   ?_assertEqual([100, 120, 144], prometheus_histogram:exponential_buckets(100, 1.2, 3)),
   ?_assertEqual([-15, -10, -5, 0, 5, 10, infinity], LinearBuckets),
   ?_assertEqual([100, 120, 144, infinity], ExpBuckets)].

test_int(_) ->
  prometheus_histogram:new([{name, http_request_duration_milliseconds},
                            {labels, [method]},
                            {buckets, [100, 300, 500, 750, 1000]},
                            {help, "Http Request execution time"}]),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 95),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 100),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 102),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 150),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 250),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 75),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 350),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 550),
  prometheus_histogram:observe(http_request_duration_milliseconds, [get], 950),
  Value = prometheus_histogram:value(http_request_duration_milliseconds, [get]),
  prometheus_histogram:reset(http_request_duration_milliseconds, [get]),
  RValue = prometheus_histogram:value(http_request_duration_milliseconds, [get]),
  [?_assertEqual({[3, 3, 1, 1, 1, 0], 2622}, Value),
   ?_assertEqual({[0, 0, 0, 0, 0, 0], 0}, RValue)].

test_double(_) ->
  prometheus_histogram:new([{name, http_request_duration_milliseconds},
                            {labels, [method]},
                            {buckets, [100, 300, 500, 750, 1000]},
                            {help, "Http Request execution time"}]),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 500.2),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 150.4),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 450.5),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 850.3),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 750.9),
  prometheus_histogram:dobserve(http_request_duration_milliseconds, [post], 1650.23),
  timer:sleep(10), %% dobserve is async so lets make sure gen_server processed our increment request
  Value = prometheus_histogram:value(http_request_duration_milliseconds, [post]),
  prometheus_histogram:reset(http_request_duration_milliseconds, [post]),
  RValue = prometheus_histogram:value(http_request_duration_milliseconds, [post]),
  [?_assertEqual({[0, 1, 1, 1, 2, 1], 4352.53}, Value),
   ?_assertEqual({[0, 0, 0, 0, 0, 0], 0}, RValue)].

test_observe_duration(_) ->
  prometheus_histogram:new([{name, fun_executing_histogram}, {buckets, [0.5, 1.1]}, {help, ""}]),
  prometheus_histogram:observe_duration(fun_executing_histogram, fun () ->
                                                                     timer:sleep(1000)
                                                                 end),
  timer:sleep(10),
  {Buckets, Sum} = prometheus_histogram:value(fun_executing_histogram),

  try prometheus_histogram:observe_duration(fun_executing_histogram, fun () ->
                                                                         erlang:error({qwe})
                                                                     end)
  catch _:_ -> ok
  end,

  timer:sleep(10),
  {BucketsE, SumE} = prometheus_histogram:value(fun_executing_histogram),

  [?_assertEqual([0, 1, 0], Buckets),
   ?_assertEqual([1, 1, 0], BucketsE),
   ?_assertMatch(true, 0.9 < Sum andalso Sum < 1.2),
   ?_assertMatch(true, 0.9 < SumE andalso SumE < 1.2)].
