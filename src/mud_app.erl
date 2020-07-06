%%%-------------------------------------------------------------------
%% @doc mud public API
%% @end
%%%-------------------------------------------------------------------

-module(mud_app).

-behaviour(application).

-include("mud.hrl").

-deinfe(MUD_APPS, []).
%%-deinfe(MUD_APPS,[mud_event,mud_pool,mud_router,mud_dbase,mud_cache,mud_ecs]).


-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Pid} = mud_sup:start_link(),
    %% 加载配置
    %% 配置是必须启动的
    ok = mud_config:load(),

    %% 获取启动的组件
    ToStart = case mud_config:get_env([]) of
                  'ALL' -> ?MUD_APPS;
                  'NONE' -> [];
                  Apps1 when is_list(Apps1) -> Apps1
              end,
    %% 获取不启动的组件
    ToSkip = case mud_config:get_env([]) of
                 'ALL' -> ?MUD_APPS;
                 'NONE' -> [];
                 Apps2 when is_list(Apps2) -> Apps2
             end,
    %% 确认需要启动的
    GoStart = lists:filter(fun(App) -> not lists:member(App, ToSkip) end, ToStart),
    %% 开始启动
    ok = auto_boot(GoStart),


    {ok, Pid}.

stop(_State) ->
    ok.

%% internal functions

%% 启动组件
auto_boot(Apps) ->
    ?NOTICE("MUD starting:~p", [Apps]),
    %% 确保顺序

    %% 事件处理
%%    ?IF(lists:member(mud_event, Apps), ok = mud_event:start()),

    %% 进程池
%%    ?IF(lists:member(mud_pool, Apps), ok = mud_pool:start()),

    %% 路由处理
    ?IF(lists:member(mud_router, Apps), ok = mud_router:start()),

    %% 数据库处理
%%    ?IF(lists:member(mud_dbase, Apps), ok = mud_dbase:start()),

    %% 缓存处理
%%    ?IF(lists:member(mud_cache, Apps), ok = mud_cache:start()),

    %% ECS模型
%%    ?IF(lists:member(mud_ecs, Apps),
%%        begin
%%            ok = mud_system:start(),
%%            ok = mud_comp:start(),
%%            ok = mud_entity:start()
%%        end),

    ok.

















