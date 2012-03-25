%% The MIT License

%% Copyright (c) 2011 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx_encoder).

-export([encoder/3, clean_string/1]).

-spec encoder(Handler::module(), State::any(), Opts::jsx:opts()) -> jsx:encoder().

encoder(Handler, State, Opts) ->
    fun(JSON) ->
        start(
            JSON,
            {Handler, Handler:init(State)},
            jsx_utils:parse_opts(Opts)
        )
    end.



-include("jsx_opts.hrl").


-ifndef(error).
-define(error(Args),
    erlang:error(badarg, Args)
).
-endif.


start(Term, {Handler, State}, Opts) ->
    Handler:handle_event(end_json, value(Term, {Handler, State}, Opts)).


value(String, {Handler, State}, Opts) when is_binary(String) ->
    Handler:handle_event({string, clean_string(String, <<>>, Opts)}, State);
value(Float, {Handler, State}, _Opts) when is_float(Float) ->
    Handler:handle_event({float, Float}, State);
value(Int, {Handler, State}, _Opts) when is_integer(Int) ->
    Handler:handle_event({integer, Int}, State);
value(Literal, {Handler, State}, _Opts)
        when Literal == true; Literal == false; Literal == null ->
    Handler:handle_event({literal, Literal}, State);
value([{}], {Handler, State}, _Opts) ->
    Handler:handle_event(end_object, Handler:handle_event(start_object, State));
value([], {Handler, State}, _Opts) ->
    Handler:handle_event(end_array, Handler:handle_event(start_array, State));
value(List, {Handler, State}, Opts) when is_list(List) ->
    list_or_object(List, {Handler, State}, Opts);
value(Term, Handler, Opts) -> ?error([Term, Handler, Opts]).


list_or_object([Tuple|_] = List, {Handler, State}, Opts) when is_tuple(Tuple) ->
    object(List, {Handler, Handler:handle_event(start_object, State)}, Opts);
list_or_object(List, {Handler, State}, Opts) ->
    list(List, {Handler, Handler:handle_event(start_array, State)}, Opts).


object([{Key, Value}|Rest], {Handler, State}, Opts) ->
    object(
        Rest,
        {
            Handler,
            value(
                Value,
                {Handler, Handler:handle_event({key, clean_string(fix_key(Key), <<>>, Opts)}, State)},
                Opts
            )
        },
        Opts
    );
object([], {Handler, State}, _Opts) -> Handler:handle_event(end_object, State);
object(Term, Handler, Opts) -> ?error([Term, Handler, Opts]).


list([Value|Rest], {Handler, State}, Opts) ->
    list(Rest, {Handler, value(Value, {Handler, State}, Opts)}, Opts);
list([], {Handler, State}, _Opts) -> Handler:handle_event(end_array, State);
list(Term, Handler, Opts) -> ?error([Term, Handler, Opts]).


fix_key(Key) when is_atom(Key) -> fix_key(atom_to_binary(Key, utf8));
fix_key(Key) when is_binary(Key) -> Key.


clean_string(Bin) -> clean_string(Bin, <<>>, #opts{json_escape=true}).

clean_string(<<$\", Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $\">>, Opts);
clean_string(<<$\\, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $\\>>, Opts);
clean_string(<<$\b, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $b>>, Opts);
clean_string(<<$\f, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $f>>, Opts);
clean_string(<<$\n, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $n>>, Opts);
clean_string(<<$\r, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $r>>, Opts);
clean_string(<<$\t, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $t>>, Opts);
clean_string(<<$/, Rest/binary>>, Acc, Opts=#opts{json_escape=true, escape_forward_slash=true}) ->
    clean_string(Rest, <<Acc/binary, $\\, $/>>, Opts);
clean_string(<<16#2028/utf8, Rest/binary>>, Acc, Opts=#opts{json_escape=true, no_jsonp_escapes=true}) ->
    clean_string(Rest, <<Acc/binary, 16#2028/utf8>>, Opts);
clean_string(<<16#2029/utf8, Rest/binary>>, Acc, Opts=#opts{json_escape=true, no_jsonp_escapes=true}) ->
    clean_string(Rest, <<Acc/binary, 16#2029/utf8>>, Opts);
clean_string(<<16#2028/utf8, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, (json_escape_sequence(16#2028))/binary>>, Opts);
clean_string(<<16#2029/utf8, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) ->
    clean_string(Rest, <<Acc/binary, (json_escape_sequence(16#2029))/binary>>, Opts);
clean_string(<<C/utf8, Rest/binary>>, Acc, Opts=#opts{json_escape=true}) when C < 32 ->
    clean_string(Rest, <<Acc/binary, (json_escape_sequence(C))/binary>>, Opts);
clean_string(<<C/utf8, Rest/binary>>, Acc, Opts) when C < 16#fdd0 ->
    clean_string(Rest, <<Acc/binary, C/utf8>>, Opts);
clean_string(<<C/utf8, Rest/binary>>, Acc, Opts) when C > 16#fdef, C < 16#fffe ->
    clean_string(Rest, <<Acc/binary, C/utf8>>, Opts);
clean_string(<<C/utf8, Rest/binary>>, Acc, Opts) 
        when C > 16#ffff andalso
            C =/= 16#1fffe andalso C =/= 16#1ffff andalso
            C =/= 16#2fffe andalso C =/= 16#2ffff andalso
            C =/= 16#3fffe andalso C =/= 16#3ffff andalso
            C =/= 16#4fffe andalso C =/= 16#4ffff andalso
            C =/= 16#5fffe andalso C =/= 16#5ffff andalso
            C =/= 16#6fffe andalso C =/= 16#6ffff andalso
            C =/= 16#7fffe andalso C =/= 16#7ffff andalso
            C =/= 16#8fffe andalso C =/= 16#8ffff andalso
            C =/= 16#9fffe andalso C =/= 16#9ffff andalso
            C =/= 16#afffe andalso C =/= 16#affff andalso
            C =/= 16#bfffe andalso C =/= 16#bffff andalso
            C =/= 16#cfffe andalso C =/= 16#cffff andalso
            C =/= 16#dfffe andalso C =/= 16#dffff andalso
            C =/= 16#efffe andalso C =/= 16#effff andalso
            C =/= 16#ffffe andalso C =/= 16#fffff andalso
            C =/= 16#10fffe andalso C =/= 16#10ffff ->
    clean_string(Rest, <<Acc/binary, C/utf8>>, Opts);
%% surrogates
clean_string(<<237, X, _, Rest/binary>>, Acc, Opts=#opts{loose_unicode=true}) when X >= 160 ->
    clean_string(Rest, <<Acc/binary, 16#fffd/utf8>>, Opts);
%% private use noncharacters
clean_string(<<239, 183, X, Rest/binary>>, Acc, Opts=#opts{loose_unicode=true}) when X >= 143, X =< 175 ->
    clean_string(Rest, <<Acc/binary, 16#fffd/utf8>>, Opts);
%% u+fffe and u+ffff
clean_string(<<239, 191, X, Rest/binary>>, Acc, Opts=#opts{loose_unicode=true}) when X == 190; X == 191 ->
    clean_string(Rest, <<Acc/binary, 16#fffd/utf8>>, Opts);
%% the u+Xfffe and u+Xffff noncharacters
clean_string(<<X, Y, 191, Z, Rest/binary>>, Acc, Opts=#opts{loose_unicode=true}) when (
            (X == 240 andalso Y == 159) orelse
            (X == 240 andalso Y == 175) orelse
            (X == 240 andalso Y == 191) orelse
            (
                (X == 241 orelse X == 242 orelse X == 243) andalso
                (Y == 143 orelse Y == 159 orelse Y == 175 orelse Y == 191)
            ) orelse
            (X == 244 andalso Y == 143)
        ) andalso (Z == 190 orelse Z == 191) ->
    clean_string(Rest, <<Acc/binary, 16#fffd/utf8>>, Opts);
clean_string(<<_, Rest/binary>>, Acc, Opts=#opts{loose_unicode=true}) ->
    clean_string(Rest, <<Acc/binary, 16#fffd/utf8>>, Opts);
clean_string(<<>>, Acc, _) -> Acc;
clean_string(Bin, _Acc, Opts) -> erlang:error(badarg, [Bin, Opts]).
    
    
%% convert a codepoint to it's \uXXXX equiv.
json_escape_sequence(X) ->
    <<A:4, B:4, C:4, D:4>> = <<X:16>>,
    unicode:characters_to_binary([$\\, $u, (to_hex(A)), (to_hex(B)), (to_hex(C)), (to_hex(D))]).


to_hex(10) -> $a;
to_hex(11) -> $b;
to_hex(12) -> $c;
to_hex(13) -> $d;
to_hex(14) -> $e;
to_hex(15) -> $f;
to_hex(X) -> X + 48.    %% ascii "1" is [49], "2" is [50], etc...

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

encode(Term) -> (encoder(jsx, [], []))(Term).

encode(Term, Opts) ->
    try (encoder(jsx, [], Opts))(Term)
    catch _:_ -> {error, badjson}
    end.


encode_test_() ->    
    [
        {"naked string", ?_assertEqual(encode(<<"a string">>), [{string, <<"a string">>}, end_json])},
        {"naked integer", ?_assertEqual(encode(123), [{integer, 123}, end_json])},
        {"naked float", ?_assertEqual(encode(1.23), [{float, 1.23}, end_json])},
        {"naked literal", ?_assertEqual(encode(null), [{literal, null}, end_json])},
        {"empty object", ?_assertEqual(encode([{}]), [start_object, end_object, end_json])},
        {"empty list", ?_assertEqual(encode([]), [start_array, end_array, end_json])},
        {"simple list", ?_assertEqual(
                encode([1,2,3,true,false]),
                [
                    start_array,
                    {integer, 1},
                    {integer, 2},
                    {integer, 3},
                    {literal, true},
                    {literal, false},
                    end_array,
                    end_json
                ]
            )
        },
        {"simple object", ?_assertEqual(
                encode([{<<"a">>, true}, {<<"b">>, false}]),
                [
                    start_object,
                    {key, <<"a">>},
                    {literal, true},
                    {key, <<"b">>},
                    {literal, false},
                    end_object,
                    end_json
                ]
            )
        },
        {"complex term", ?_assertEqual(
                encode([
                    {<<"a">>, true},
                    {<<"b">>, false},
                    {<<"c">>, [1,2,3]},
                    {<<"d">>, [{<<"key">>, <<"value">>}]}
                ]),
                [
                    start_object,
                    {key, <<"a">>},
                    {literal, true},
                    {key, <<"b">>},
                    {literal, false},
                    {key, <<"c">>},
                    start_array,
                        {integer, 1},
                        {integer, 2},
                        {integer, 3},
                    end_array,
                    {key, <<"d">>},
                    start_object,
                        {key, <<"key">>},
                        {string, <<"value">>},
                    end_object,
                    end_object,
                    end_json
                ]
            )
        },
        {"atom keys", ?_assertEqual(
                encode([{key, <<"value">>}]),
                [start_object, {key, <<"key">>}, {string, <<"value">>}, end_object, end_json]
            )
        }
    ].
    
noncharacters_test_() ->
    [
        {"noncharacters - badjson",
            ?_assertEqual(check_bad(noncharacters()), [])
        },
        {"noncharacters - replaced",
            ?_assertEqual(check_replaced(noncharacters()), [])
        }
    ].

extended_noncharacters_test_() ->
    [
        {"extended noncharacters - badjson",
            ?_assertEqual(check_bad(extended_noncharacters()), [])
        },
        {"extended noncharacters - replaced",
            ?_assertEqual(check_replaced(extended_noncharacters()), [])
        }
    ].

surrogates_test_() ->
    [
        {"surrogates - badjson",
            ?_assertEqual(check_bad(surrogates()), [])
        },
        {"surrogates - replaced",
            ?_assertEqual(check_replaced(surrogates()), [])
        }
    ].

reserved_test_() ->
    [
        {"reserved noncharacters - badjson",
            ?_assertEqual(check_bad(reserved_space()), [])
        },
        {"reserved noncharacters - replaced",
            ?_assertEqual(check_replaced(reserved_space()), [])
        }
    ].
    
good_characters_test_() ->
    [
        {"acceptable codepoints",
            ?_assertEqual(check_good(good()), [])
        },
        {"acceptable extended",
            ?_assertEqual(check_good(good_extended()), [])
        }
    ].

malformed_test_() ->
    [
        {"malformed codepoint with 1 byte", ?_assertError(badarg, encode(<<128>>))},
        {"malformed codepoint with 2 bytes", ?_assertError(badarg, encode(<<128, 192>>))},
        {"malformed codepoint with 3 bytes", ?_assertError(badarg, encode(<<128, 192, 192>>))},
        {"malformed codepoint with 4 bytes", ?_assertError(badarg, encode(<<128, 192, 192, 192>>))}
    ].

malformed_replaced_test_() ->
    F = <<16#fffd/utf8>>,
    [
        {"malformed codepoint with 1 byte",
            ?_assertEqual(
                [{string, <<F/binary>>}, end_json],
                encode(<<128>>, [loose_unicode])
            )
        },
        {"malformed codepoint with 2 bytes",
            ?_assertEqual(
                [{string, <<F/binary, F/binary>>}, end_json],
                encode(<<128, 192>>, [loose_unicode])
            )
        },
        {"malformed codepoint with 3 bytes",
            ?_assertEqual(
                [{string, <<F/binary, F/binary, F/binary>>}, end_json],
                encode(<<128, 192, 192>>, [loose_unicode])
            )
        },
        {"malformed codepoint with 4 bytes",
            ?_assertEqual(
                [{string, <<F/binary, F/binary, F/binary, F/binary>>}, end_json],
                encode(<<128, 192, 192, 192>>, [loose_unicode])
            )
        }
    ].

check_bad(List) ->
    lists:dropwhile(fun({_, {error, badjson}}) -> true ; (_) -> false end,
        check(List, [], [])
    ).

check_replaced(List) ->
    lists:dropwhile(fun({_, [{string, <<16#fffd/utf8>>}|_]}) -> true
            ; (_) -> false 
        end,
        check(List, [loose_unicode], [])
    ).

check_good(List) ->
    lists:dropwhile(fun({_, [{string, _}|_]}) -> true ; (_) -> false end,
        check(List, [], [])
    ).

check([], _Opts, Acc) -> Acc;
check([H|T], Opts, Acc) ->
    R = encode(to_fake_utf(H, utf8), Opts),
    check(T, Opts, [{H, R}] ++ Acc).
    


noncharacters() -> lists:seq(16#fffe, 16#ffff).
    
extended_noncharacters() ->
    [16#1fffe, 16#1ffff, 16#2fffe, 16#2ffff]
        ++ [16#3fffe, 16#3ffff, 16#4fffe, 16#4ffff]
        ++ [16#5fffe, 16#5ffff, 16#6fffe, 16#6ffff]
        ++ [16#7fffe, 16#7ffff, 16#8fffe, 16#8ffff]
        ++ [16#9fffe, 16#9ffff, 16#afffe, 16#affff]
        ++ [16#bfffe, 16#bffff, 16#cfffe, 16#cffff]
        ++ [16#dfffe, 16#dffff, 16#efffe, 16#effff]
        ++ [16#ffffe, 16#fffff, 16#10fffe, 16#10ffff].

surrogates() -> lists:seq(16#d800, 16#dfff).

reserved_space() -> lists:seq(16#fdd0, 16#fdef).

good() -> lists:seq(1, 16#d7ff) ++ lists:seq(16#e000, 16#fdcf) ++ lists:seq(16#fdf0, 16#fffd).
            
good_extended() -> lists:seq(16#100000, 16#10fffd).

%% erlang refuses to encode certain codepoints, so fake them all
to_fake_utf(N, utf8) when N < 16#0080 -> <<N:8>>;
to_fake_utf(N, utf8) when N < 16#0800 ->
    <<0:5, Y:5, X:6>> = <<N:16>>,
    <<2#110:3, Y:5, 2#10:2, X:6>>; 
to_fake_utf(N, utf8) when N < 16#10000 ->
    <<Z:4, Y:6, X:6>> = <<N:16>>,
    <<2#1110:4, Z:4, 2#10:2, Y:6, 2#10:2, X:6>>;
to_fake_utf(N, utf8) ->
    <<0:3, W:3, Z:6, Y:6, X:6>> = <<N:24>>,
    <<2#11110:5, W:3, 2#10:2, Z:6, 2#10:2, Y:6, 2#10:2, X:6>>.

-endif.