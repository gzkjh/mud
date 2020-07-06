%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 06. 7月 2020 21:00
%%%-------------------------------------------------------------------
-module(mud_proplists).
-author("Commando").

-include("mud.hrl").

%% API
-export([merge/2, get_value_recursive/2, get_value_recursive/3, get_value_multi/2]).


%% @doc
%% 按层级递归获取数据
%% @end
-spec get_value_recursive(list(), proplists:proplist()) -> term().
get_value_recursive(KeyList, Data) ->
    get_value_recursive(KeyList, Data, ?undefined).

%% @doc
%% 按层级递归获取数据，没有的话返回默认值
%% @end
-spec get_value_recursive(list(), proplists:proplist(), term()) -> term().
get_value_recursive([], Data, _Default) -> Data;
get_value_recursive([Key | Rest], Data, Default) when is_list(Data) ->
    case proplists:get_value(Key, Data) of
        NewData when NewData =/= ?undefined ->
            get_value_recursive(Rest, NewData, Default);
        _ ->
            Default
    end;
get_value_recursive(_Key, _Data, Default) ->
    Default.

get_value_multi(KeyList, Data) when is_list(KeyList) ->
    Out = lists:foldl(
        fun(MxKey, Ret) ->
            R = case MxKey of
                    {Key, Default} -> proplists:get_value(Key, Data, Default);
                    Key -> proplists:get_value(Key, Data)
                end,
            [R | Ret]
        end, [], KeyList),
    lists:reverse(Out).


%% @doc
%% 类似 maps:merge
%% 合并两个proplists，后面的会覆盖前面的
%% @end
merge(L1, L2) ->
    Keys2 = proplists:get_keys(L2),
    lists:foldl(
        fun(K2, L) ->
            %% 旧值
            V1 = proplists:get_value(K2, L1, ?undefined),
            %% 新值
            V2 = proplists:get_value(K2, L2),
            %% 如果两个值都是proplists，则递归合并
            IsMerge = is_proplists(V1) andalso is_proplists(V2),
            %% 是否定义
            IsDefined = proplists:is_defined(K2, L),
            if
                IsMerge ->
                    [{K2, merge(V1, V2)} | proplists:delete(K2, L)];
                IsDefined ->
                    [{K2, V2} | proplists:delete(K2, L)];
                ?true ->
                    [{K2, V2} | L]
            end
        end, L1, Keys2).


is_proplists(Ls) when is_list(Ls) ->
    lists:all(
        fun(Elem) ->
            erlang:is_tuple(Elem) orelse erlang:is_atom(Elem)
        end, Ls);
is_proplists(_Ls) -> ?false.





























