%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 06. 7月 2020 21:16
%%%-------------------------------------------------------------------
-module(mud_file).
-author("Commando").


-include("mud.hrl").

%% API
-export([get_all_mod/1, get_mod_with_behavior/2]).


-spec get_all_mod(string()|atom()) -> [atom()].
get_all_mod(App) ->
    case code:lib_dir(App) of
        {error, _} ->
            ?ERROR("~p isn't an App", [App]),
            [];
        Path ->
            %% 获取文件名
            Ls = filelib:wildcard(Path ++ "/**/*.beam"),
            %% 转换为模块名字
            [list_to_atom(filename:basename(Fn, ".beam")) || Fn <- Ls]
    end.


%% 按指定行为查询模块
-spec get_mod_with_behavior(atom(), [atom()]) -> [atom()].
get_mod_with_behavior(Behav, ModList) ->
    lists:foldl(
        fun(Elem, In) ->
            %% 获取模块属性
            Attr = Elem:module_info(attributes),
            %% 两种写法都可以，所以都要获取
            BehavList1 = proplists:get_value(behavior, Attr, []),
            BehavList2 = proplists:get_value(behaviour, Attr, []),
            case lists:any(fun(E) -> E =:= Behav end, BehavList1 ++ BehavList2) of
                ?true -> [Elem | In];
                ?false -> In
            end
        end, [], ModList).




















