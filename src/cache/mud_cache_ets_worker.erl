%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 10. 7月 2020 20:40
%%%-------------------------------------------------------------------
-module(mud_cache_ets_worker).
-author("Commando").


-include("mud_cache.hrl").
-include("mud.hrl").

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(atom(), map()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Opts) ->
    PidName = mud_cache_lib:make_table_name(Name),
    gen_server:start_link({local, PidName}, ?MODULE, [Name, Opts], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([Name, Opts]) ->
    %% 主键，必须参数
    #{primary_key := KeyPos} = Opts,

    %% 检查循环时间
    SaveTime =
        case maps:get(save_interval, Opts, 0) of
            0 -> 0; %% 不保存
            {_Sec, SecLoop} -> SecLoop;
            Sec when is_integer(Sec) -> Sec
        end,

    %% 预加载
    Preload = ?IF(maps:get(preload, Opts, ?false) =:= ?true, ?true, ?false),
    %% 数据失效时间
    InvalidTime = ?IF(Preload, 0, maps:get(invalid_interval, Opts, 0)),

    %% 循环时间
    %% 如果有保存时间，则按保存时间
    %% 如果有过期时间，且过期时间不超过10分钟，那就按过期时间
    %% 如果有过期时间，且超过10分钟，那就按10分钟
    %% 都没有，则0
    LoopTime = ?IF(SaveTime > 0, SaveTime, ?IF(InvalidTime > 0, ?IF(InvalidTime < 600, InvalidTime, 600), 0)),

    %% 开启定时器
    First = rand:uniform(60), %% 如果没有设置初始时间，则随机分布在1分钟内
    ?IF(LoopTime > 0, erlang:send_after(?SECOND_TO_MS(First), self(), 'loop_task@self')),

    %% ets相关
    Tweaks = maps:get(tweaks, Opts, []),
    EtsOpt = make_options(Tweaks, [named_table]),    %% set,protected 这2个是默认的
    %% 构造表名字
    EtsName = mud_cache_lib:make_table_name(Name),
    %% 创建
    ets:new(EtsName, EtsOpt),

    %% 索引表
    EtsNameIdx2 =
        if
            is_tuple(KeyPos) ->  %% 有需要才创建
                EtsNameIdx = mud_cache_lib:make_idx_table_name(Name),
                ets:new(EtsNameIdx, [set, named_table, private]),
                EtsNameIdx;
            ?true ->
                ?undefined
        end,

    %% 状态
    State = #state{
        name = Name,
        tbl = EtsName,
        tbl_idx = EtsNameIdx2,
        keypos = KeyPos,
        save_interval = SaveTime,
        invalid_interval = InvalidTime,
        loop_timeout = LoopTime
    },

    %% 预加载
    ?IF(Preload, do_preload_datas(State)),

    %% 返回State
    {ok, State}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({lookup, Key}, _From, State = #state{}) ->
    Reply = do_lookup(Key, State),
    {reply, Reply, State};
handle_call({insert, Value}, _From, State = #state{}) ->
    Key = mud_cache_lib:get_key(Value, State),
    case do_insert(Key, Value, State) of
        ?true ->
            %% 安排保存和老化
            State2 = mud_cache_lib:schedule_task(Key, State),
            {reply, ?true, State2};
        ?false ->
            {reply, ?false, State}
    end;
handle_call({update, Value}, _From, State = #state{}) ->
    State2 = do_update(Value, State),
    {reply, ok, State2};
handle_call({delete, Key}, _From, State = #state{}) ->
    State2 = do_delete(Key, State),
    {reply, ok, State2};
handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State = #state{}) ->
    {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
%% 插入数据
handle_info({insert, Value}, State = #state{}) ->
    Key = mud_cache_lib:get_key(Value, State),
    case do_insert(Key, Value, State) of
        ?true ->
            %% 安排保存和老化
            State2 = mud_cache_lib:schedule_task(Key, State),
            {noreply, State2};
        ?false ->
            {noreply, State}
    end;
%% 更新
handle_info({update, Value}, State = #state{}) ->
    State2 = do_update(Value, State),
    {noreply, State2};
%% 安排丢弃数据
handle_info({expire, Key, Sec}, State = #state{}) ->
    State2 = do_expire(Key, Sec, State),
    {noreply, State2};
%% 删除数据
handle_info({delete, Key}, State = #state{}) ->
    State2 = do_delete(Key, State),
    {noreply, State2};
%% 保存数据
handle_info({save, Key}, State = #state{}) ->
    State2 = do_save(Key, State),
    {noreply, State2};
%% 保存所有数据
handle_info(save_all, State = #state{to_save = ToSave}) ->
    State2 = do_task_save(ToSave, State),
    {noreply, State2};
%% 定时任务
handle_info(Msg = 'loop_task@self', State = #state{loop_timeout = Sec, to_save = ToSave, to_expire = ToExpire}) ->
    %% 保存
    do_task_save(ToSave, State),
    %% 计算哪些需要删掉
    {ToExpire2, NowExpire} = mud_cache_lib:analyze_expire(ToExpire),

    %% 执行数据老化
    do_task_expire(NowExpire, State),

    %% 重新给自己发信息
    erlang:send_after(?SECOND_TO_MS(Sec), self(), Msg),

    State2 = State#state{
        to_save = [],
        to_expire = ToExpire2
    },
    {noreply, State2};
%% 关闭服务
handle_info(stop, State = #state{to_save = ToSave}) ->
    State2 = do_task_save(ToSave, State),
    {stop, normal, State2};
handle_info(_Info, State = #state{}) ->
    {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State = #state{tbl = Tbl, tbl_idx = TblIdx}) ->
    %% 释放ets
    ets:delete(Tbl),
    ?IF(TblIdx =/= ?undefined, ets:delete(TblIdx)),
    ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

make_options([], Ret) -> Ret;
make_options([read_concurrency | Rest], Ret) ->
    make_options(Rest, [{read_concurrency, ?true} | Ret]);
make_options([write_concurrency | Rest], Ret) ->
    make_options(Rest, [{write_concurrency, ?true} | Ret]).


get_simple_key_from_ets(State, Key) ->
    #state{tbl = Tbl} = State,
    case ets:lookup(Tbl, Key) of
        [] -> ?undefined;
        [{_, Data}] -> Data
    end.


get_half_key_from_ets(State, KeyOne) ->
    #state{tbl_idx = TblIdx} = State,
    case ets:lookup(TblIdx, KeyOne) of
        [] ->
            ?undefined;
        [{_KeyOne, KeyTwoList}] ->
            [get_simple_key_from_ets(State, {KeyOne, KeyTwo}) || KeyTwo <- KeyTwoList]
    end.

get_simple_key_from_db(State = #state{save_interval = Ti, tbl_idx = ?undefined}, Key) when Ti =/= 0 ->
    #state{name = Name} = State,
    case mud_cache_lib:db_select(Name, Key) of
        [] ->
            ?undefined;
        [Data | _] ->
            %% 写入缓存
            store_to_ets(State, Key, Data),
            Data
    end;
get_simple_key_from_db(_State, _Key) ->
    ?undefined.

store_to_ets(#state{tbl = Tbl}, Key, Value) ->
    %% 用insert_new避免覆盖
    ets:insert_new(Tbl, {Key, Value}).

%% 把主键索引起来
store_to_ets_idx(#state{tbl_idx = Tbl}, KeyOne, KeyTwoList) ->
    ets:insert(Tbl, {KeyOne, KeyTwoList}),
    ok.






























