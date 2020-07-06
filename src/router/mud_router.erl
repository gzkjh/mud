%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 06. 7月 2020 19:20
%%%-------------------------------------------------------------------
-module(mud_router).
-author("Commando").

-behaviour(gen_server).

-include("mud.hrl").
-include("mud_router.hrl").

%% API
-export([add_route/2, add_route/3, replace_route/3,
    module_expired/1, delete_expired/0, remove_route/1, lookup/1, lookup/2]).

-export([start_link/0, start/0, stop/0, i/0, i/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================


%% @doc
%% 添加路由
%% @see add_route/3
%% @end
-spec add_route(atom(), mfa()) -> ok.
add_route(Key, Mfa) ->
    add_route(Key, Mfa, ?undefined).

%% @doc
%% 添加路由
%% @end
-spec add_route(atom(), mfa(), term()) -> ok.
add_route(Key, Mfa, Extra) ->
    gen_server:call(?MODULE, {add_route, Key, Mfa, Extra}).

%% @doc
%% 替换路由
%% @end
replace_route(Key, Mfa, Extra) ->
    gen_server:call(?MODULE, {replace_route, Key, Mfa, Extra}).

%% @doc
%% 指定模块的对应路由过期
%%
%% ```
%% 一般是更新模块的时候使用
%% '''
%% @end
module_expired(Mod) ->
    %% 这个函数会在系统启动的时候调用，所以判断一下
    case erlang:whereis(?MODULE) of
        ?undefined -> ok;
        _ -> gen_server:call(?MODULE, {module_expired, Mod})
    end.

%% @doc
%% 删除过期路由
%%
%% ```
%% 一般是更新模块的时候使用
%% '''
%% @end
delete_expired() ->
    gen_server:call(?MODULE, delete_expired).


%% @doc
%% 移除指定路由
%% @end
remove_route(Key) ->
    ets:delete(?ETS_ROUTER, Key),
    ok.

%% @doc
%% 查找路由
%%
%% ```
%%
%% '''
%% @end
-spec lookup(atom()) -> [{function(), integer(), term()}].
lookup(Cmd) ->
    case ets:lookup(?ETS_ROUTER, Cmd) of
        [] ->
            [];
        [#routes{rs = Rs}] ->
            [{Fun, Arity, Extra} || #one_route{mfa = {_M, _F, Arity}, ext = Extra, func = Fun} <- Rs]
    end.

%% @doc
%% 查找路由
%%
%% ```
%% 自定义过滤函数
%% '''
%% @end
-spec lookup(atom(), function()) -> [{function(), integer(), term()}].
lookup(Cmd, Pred) ->
    case ets:lookup(?ETS_ROUTER, Cmd) of
        [] ->
            [];
        [#routes{rs = Rs}] ->
            Rs1 = lists:filter(
                fun(Elem) ->
                    #one_route{ext = Ext, _ = '_'} = Elem,
                    Pred(Ext)
                end, Rs),
            [{Fun, Arity, Extra} || #one_route{mfa = {_M, _F, Arity}, ext = Extra, func = Fun} <- Rs1]
    end.

%% @doc
%% 启动路由服务
%% @end
start() ->
    Child = #{
        id => ?MODULE,
        start => {?MODULE, start_link, []},
        restart => permanent,   %% 一直重启
        shutdown => 2000,
        type => worker,
        modules => [?MODULE]
    },
    {ok, _} = supervisor:start_child(mud_sup, Child),
    ok.

%% @doc
%% 关闭路由服务
%% @end
stop() ->
    supervisor:terminate_child(mud_sup, ?MODULE).

%% @private
%% @doc
%% 查询所有路由信息，调试用
%% @end
i() ->
    show_routes(ets:first(?ETS_ROUTER)),
    ok.

%% @private
%% @doc
%% 查询指定路由信息，调试用
%% @end
i(Key) ->
    case ets:lookup(?ETS_ROUTER, Key) of
        [] ->
            ?NOTICE("route ~p not exist!", [Key]);
        [#routes{rs = Rs}] ->
            L2 = [{Mfa, Ext} || #one_route{mfa = Mfa, ext = Ext} <- Rs],
            ?NOTICE("~p => ~p", [Key, L2])
    end,
    ok.

%% @private
%% @doc Spawns the server and registers the local name (unique)
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    ?INFO("---------- ~p:~p/~p !!!", [?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY]),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
    {ok, State} | {ok, State, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    %% 创建ets
    ets:new(?ETS_ROUTER, [
        set,
        named_table,
        protected,
        {keypos, #routes.cmd},
        {read_concurrency, ?true}
    ]),
    {ok, ?undefined}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State) ->
    {reply, Reply :: term(), NewState} |
    {reply, Reply :: term(), NewState, timeout() | hibernate} |
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState} |
    {stop, Reason :: term(), NewState}).
handle_call({add_route, Key, Mfa, Extra}, _From, State) ->
    Reply = do_add_route(Key, Mfa, Extra),
    {reply, Reply, State};
handle_call({replace_route, Key, Mfa, Extra}, _From, State) ->
    Reply = do_replace_route(Key, Mfa, Extra),
    {reply, Reply, State};
handle_call({module_expired, Mod}, _From, State) ->
    Reply = do_module_expired(Mod),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = do_delete_expired(),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason :: term(), NewState}).
handle_cast(_Request, State) ->
    {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason :: term(), NewState}).
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State) -> term()).
terminate(_Reason, _State) ->
    ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State,
    Extra :: term()) ->
    {ok, NewState} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================



show_routes('$end_of_table') -> ok;
show_routes(Key) ->
    case ets:lookup(?ETS_ROUTER, Key) of
        [] -> ?skip;
        [#routes{rs = Rs}] ->
            Rs2 = [{M, Ext} || #one_route{mfa = {M, _, _}, ext = Ext} <- Rs],
            ?NOTICE("~p => ~p", [Key, Rs2])
    end,
    Next = ets:next(?ETS_ROUTER, Key),
    show_routes(Next).


make_func({_Mod, Fun, 2}) when is_function(Fun) -> Fun;
make_func({Mod, Fun, Arity}) -> fun Mod:Fun/Arity.


make_route(Mfa, Extra, Flag) ->
    Fun = make_func(Mfa),
    #one_route{mfa = Mfa, ext = Extra, func = Fun, flag = Flag}.

%% 增加路由，保证不重复
do_add_route(Key, Mfa, Extra) ->
    %% 先锁定
    ets:safe_fixtable(?ETS_ROUTER, ?true),
    Route = make_route(Mfa, Extra, ?undefined),
    case ets:lookup(?ETS_ROUTER, Key) of
        [] ->
            NewRoute = #routes{cmd = Key, rs = [Route]},
            ets:insert_new(?ETS_ROUTER, NewRoute);
        [#routes{rs = Rs} = OldRoutes] ->
            case is_exist_route(Route, Rs) of
                ?false ->
                    ets:insert(?ETS_ROUTER, OldRoutes#routes{rs = [Route | Rs]});
                ?true ->
                    %% 已经存在，跳过不增加
                    ?WARNING("route ~p ~p exists!", [Key, Mfa]),
                    ?skip
            end
    end,
    ets:safe_fixtable(?ETS_ROUTER, ?false),
    ok.


do_replace_route(Key, Mfa, Extra) ->
    %% 先锁定ets
    ets:safe_fixtable(?ETS_ROUTER, ?true),
    Route = make_route(Mfa, Extra, ?undefined),
    case ets:lookup(?ETS_ROUTER, Key) of
        [] ->
            NewRoute = #routes{cmd = Key, rs = [Route]},
            ets:insert_new(?ETS_ROUTER, NewRoute);
        [#routes{rs = Rs} = OldRoutes] ->
            %% 替换函数
            Fun =
                fun(Elem, {Flag, In}) ->
                    case Elem of
                        #one_route{mfa = Mfa} -> %% 相同的mfa表示同一个路由
                            {?true, [Route | In]};
                        _ ->
                            {Flag, [Elem | In]}
                    end
                end,
            %% 开始尝试替换
            case lists:foldl(Fun, {?false, []}, Rs) of
                {?true, Rs1} -> %% 替换成功
                    ets:insert(?ETS_ROUTER, OldRoutes#routes{rs = Rs1});
                {?false, Rs1} -> %% 没有替换，插入新的
                    ets:insert(?ETS_ROUTER, OldRoutes#routes{rs = [Route | Rs1]})
            end
    end,
    ets:safe_fixtable(?ETS_ROUTER, ?false),
    ok.


do_module_expired(Mod) ->
    %% 先锁定ets
    ets:safe_fixtable(?ETS_ROUTER, ?true),
    %% 开始遍历
    Key = ets:first(?ETS_ROUTER),
    do_module_expired_loop(Key, Mod),
    ets:safe_fixtable(?ETS_ROUTER, ?false),
    ok.

%% 使对应的模块路由过期
do_module_expired_loop('$end_of_table', _Mod) -> ok;
do_module_expired_loop(Key, Mod) ->
    case ets:lookup(?ETS_ROUTER, Key) of
        [] ->
            ?skip;
        [#routes{rs = Rs} = Routes] ->
            Rs1 = lists:foldl(
                fun(Elem, In) ->
                    #one_route{mfa = Mfa, ext = Extra} = Elem,
                    case Mfa of
                        {Mod, _, _} ->
                            %% 新路由，标志位过期
                            Route = make_route(Mfa, Extra, expired),
                            [Route | In];
                        _ ->
                            [Elem | In]
                    end
                end, [], Rs),
            %% 更新
            ets:insert(?ETS_ROUTER, Routes#routes{rs = Rs1})
    end,
    %% 下一个
    Next = ets:next(?ETS_ROUTER, Key),
    do_module_expired_loop(Next, Mod).

do_delete_expired() ->
    %% 先锁定ets
    ets:safe_fixtable(?ETS_ROUTER, ?true),
    %% 开始遍历
    Key = ets:first(?ETS_ROUTER),
    do_delete_expired_loop(Key),
    ets:safe_fixtable(?ETS_ROUTER, ?false),
    ok.


do_delete_expired_loop('$end_of_table') -> ok;
do_delete_expired_loop(Key) ->
    case ets:lookup(?ETS_ROUTER, Key) of
        [] ->
            ?skip;
        [#routes{rs = Rs} = Routes] ->
            Rs1 = lists:filter(fun(E) -> E#one_route.flag =/= expired end, Rs),
            %% 更新
            ets:insert(?ETS_ROUTER, Routes#routes{rs = Rs1})
    end,
    %% 下一个
    Next = ets:next(?ETS_ROUTER, Key),
    do_delete_expired_loop(Next).


%% 看看路由是否存在
is_exist_route(Route, Rs) ->
    #one_route{mfa = Mfa} = Route,
    lists:any(
        fun(Elem) ->
            case Elem of
                #one_route{mfa = Mfa} -> ?true;
                _ -> ?false
            end
        end, Rs).














