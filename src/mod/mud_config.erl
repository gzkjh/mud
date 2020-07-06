%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 06. 7月 2020 20:49
%%%-------------------------------------------------------------------
-module(mud_config).
-author("Commando").


-include("mud.hrl").

%% API
-export([]).



load() ->
    %% 获取配置目录
    AllCfgDirs = application:get_env(mud, config_dir, ["config_x"]),
    %% 开始载入
    lists:foreach(fun load_dir/1, AllCfgDirs),
    ok.


%% 载入某个目录下的配置
load_dir(Dir) ->
    %% 获取所有配置文件
    AllCfgFiles = filelib:wildcard(filename:join(Dir, "*.config")),
    %% 开始读取文件内容
    lists:foreach(
        fun(Fn) ->
            Mod = list_to_atom(filename:basename(Fn, ".config")),
            App = ?IF(is_application(Mod), Mod, mud),
            ?INFO("load ~p to ~p", [Fn, App]),
            case file:consult(Fn) of
                {ok, []} ->
                    ?skip;
                {ok, [Data]} ->
                    %% 合并数据
                    merge_conf(App, Mod, Data);
                {error, Reason} ->
                    ?WARNING("load config ~p error ~p", [Fn, Reason]),
                    ?skip
            end
        end, AllCfgFiles),
    %% 开始查找子目录
    case file:list_dir(Dir) of
        {ok, All} ->
            %% 拼接全路径
            All2 = [filename:join(Dir, X) || X <- All],
            %% 过滤目录
            AllSubDir = lists:filter(fun(E) -> filelib:is_dir(E) end, All2),
            %% 开始遍历子目录
            lists:foreach(fun(SubDir) -> load_dir(SubDir) end, AllSubDir);
        {error, _} ->
            ?skip
    end,
    ok.

%% 判断是否application
is_application(App) when is_atom(App) ->
    application:load(App),
    Apps = application:loaded_applications(),
    lists:keymember(App, 1, Apps).


%% 合并配置
merge_conf(App, App, Data) ->
    %% todo 以后21.3版本有更好的方式去set_env
    OldData = application:get_all_env(App),
    Data2 = mud_proplists:merge(OldData, Data),   %% 递归合并
    lists:foreach(fun({Par, Val}) -> application:set_env(App, Par, Val) end, Data2);
merge_conf(App, Mod, Data) ->
    OldData = application:get_all_env(App),
    Data2 = mud_proplists:merge(OldData, [{Mod, Data}]),   %% 递归合并
    lists:foreach(fun({Par, Val}) -> application:set_env(App, Par, Val) end, Data2).

























