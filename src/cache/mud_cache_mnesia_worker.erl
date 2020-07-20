%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 10. 7月 2020 20:40
%%%-------------------------------------------------------------------
-module(mud_cache_mnesia_worker).
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


    %% 构造表名字
    TblName = mud_cache_lib:make_table_name(Name),
    %% 初始化表格
    init_table(TblName),

    %% 索引表
    IdxTblName =
        if
            is_tuple(KeyPos) ->  %% 有需要才创建
                NameIdx = mud_cache_lib:make_idx_table_name(Name),
                init_idx_table(NameIdx),
                NameIdx;
            ?true ->
                ?undefined
        end,

    %% 状态
    State = #state{
        name = Name,
        tbl = TblName,
        tbl_idx = IdxTblName,
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
handle_info(Info, State = #state{}) ->
    ?WARNING("~p unhandle info ~p", [?MODULE, Info]),
    {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    %% mnesia是跨节点的，某个节点关闭，就不清理数据了
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



get_simple_key_from_mnesia(State, Key) ->
    #state{tbl = Tbl} = State,
    case mnesia:dirty_read(Tbl, Key) of
        [] -> ?undefined;
        [#mdv{value = Data}] -> Data
    end.


get_half_key_from_mnesia(State, KeyOne) ->
    #state{tbl_idx = TblIdx} = State,
    case mnesia:dirty_read(TblIdx, KeyOne) of
        [] ->
            ?undefined;
        [#mdv{value = KeyTwoList}] ->
            [get_simple_key_from_mnesia(State, {KeyOne, KeyTwo}) || KeyTwo <- KeyTwoList]
    end.

get_simple_key_from_db(State = #state{save_interval = Ti, tbl_idx = ?undefined}, Key) when Ti =/= 0 ->
    #state{name = Name} = State,
    case mud_cache_lib:db_select(Name, Key) of
        [] ->
            ?undefined;
        [Data | _] ->
            %% 写入缓存
            store_to_mnesia(State, Key, Data),
            Data
    end;
get_simple_key_from_db(_State, _Key) ->
    ?undefined.

store_to_mnesia(#state{tbl = Tbl}, Key, Value) ->
    %% 用insert_new避免覆盖
    try
        mnesia:dirty_write(Tbl, #mdv{key = Key, value = Value}),
        ?true
    catch
        _Type:Reason ->
            ?ERROR("store_to_mnesia false ~p", [Reason]),
            ?false
    end.

%% 把主键索引起来
store_to_mnesia_idx(#state{tbl_idx = Tbl}, KeyOne, KeyTwoList) ->
    mnesia:dirty_write(Tbl, #mdv{key = KeyOne, value = KeyTwoList}),
    ok.


load_db_by_half_key(#state{tbl_idx = ?undefined}, _KeyOne) ->
    ok;
load_db_by_half_key(State = #state{tbl_idx = TblIdx, save_interval = Save}, KeyOne) ->
    case mnesia:dirty_read(TblIdx, KeyOne) of
        %% 从来没加载过
        [] ->
            if
                Save =:= 0 -> mnesia:dirty_write(TblIdx, #mdv{key = KeyOne, value = []});    %% 没存档
                ?true -> do_load_from_db_by_half_key(State, KeyOne) %% 存档的
            end;
        _ -> ?skip
    end,
    ok.

do_load_from_db_by_half_key(State = #state{name = Name}, KeyOne) ->
    DataList = mud_cache_lib:db_select(Name, primary_half_key, KeyOne),
    %% 生成map格式
    {KeyTwoList, DataMap} =
        lists:foldl(
            fun(V, {Keys, Datas}) ->
                K = mud_cache_lib:get_key(V, State),
                {_K1, K2} = K,
                %% 存入ets
                store_to_mnesia(State, K, V),
                {[K2 | Keys], Datas#{K => V}}
            end, {[], #{}}, DataList),
    %% 写入索引缓存
    store_to_mnesia_idx(State, KeyOne, KeyTwoList),
    DataMap.


add_half_key({KeyOne, KeyTwo}, #state{tbl_idx = TblIdx} = State) when TblIdx =/= ?undefined ->
    load_db_by_half_key(State, KeyOne),
    [#mdv{value = KeyTwoList}] = mnesia:dirty_read(TblIdx, KeyOne),
    case lists:member(KeyTwo, KeyTwoList) of
        ?true -> ?skip;
        ?false -> mnesia:dirty_write(TblIdx, #mdv{key = KeyOne, value = [KeyTwo | KeyTwoList]})
    end,
    ok;
add_half_key(_Key, _State) ->
    ok.


sub_half_key({KeyOne, KeyTwo}, #state{tbl_idx = TblIdx}) when TblIdx =/= ?undefined ->
    case mnesia:dirty_read(TblIdx, KeyOne) of
        [#mdv{value = KeyTwoList}] ->
            %% 删除
            KeyTwoList2 = lists:delete(KeyTwo, KeyTwoList),
            %% 更新
            mnesia:dirty_write(TblIdx, #mdv{key = KeyOne, value = KeyTwoList2}),
            ok;
        _ ->
            ok
    end;
sub_half_key(_Key, _State) -> ok.



remove_half_key({KeyOne, _KeyTwo}, #state{tbl_idx = TblIdx}) when TblIdx =/= ?undefined ->
    mnesia:dirty_delete(TblIdx, KeyOne);
remove_half_key(_Key, _State) -> ok.



do_lookup(Key, State = #state{tbl_idx = ?undefined}) -> %% 简单键
    get_simple_key_from_db(State, Key);
do_lookup({KeyOne, _} = Key, State) ->
    load_db_by_half_key(State, KeyOne),
    get_simple_key_from_mnesia(State, Key);
do_lookup(KeyOne, State) when is_number(KeyOne);is_binary(KeyOne);is_atom(KeyOne);is_list(KeyOne) ->
    load_db_by_half_key(State, KeyOne),
    get_half_key_from_mnesia(State, KeyOne).


do_insert(Key, Value, State) ->
    #state{name = Name, tbl = Tbl, save_interval = Ti} = State,
    %% 先看看是否需要添加这个键
    %% 这里先判断，再去insert_new，否则可能影响判断
    add_half_key(Key, State),
    %% 开始插入
    case store_to_mnesia(State, Key, Value) of
        ?true ->
            ?IF(Ti > 0, mud_cache_lib:db_insert(Name, Value)),
            ?true;
        ?false ->
            ?ERROR("Value ~p in ~p already exists!", [Value, Tbl]),
            ?false
    end.


do_update(Value, State) ->
    #state{tbl = Tbl} = State,
    Key = mud_cache_lib:get_key(Value, State),

    %% 这里是防止数据老化导师数据丢失，因此每次都会判断一下是否需要加载
    %% ets_idx是bag类型，不会导致重新插入
    add_half_key(Key, State),

    %% 更新缓存
    mnesia:dirty_write(Tbl, #mdv{key = Key, value = Value}),

    %% 安排保存和老化任务
    State2 = mud_cache_lib:schedule_task(Key, State),
    State2.

do_delete(Key, State) ->
    #state{
        name = Name,
        tbl = Tbl,
        save_interval = Ti,
        to_save = ToSave,
        to_expire = ToExpire
    } = State,
    %% 移除单个复合索引
    sub_half_key(Key, State),
    %% 删除缓存
    mnesia:dirty_delete(Tbl, Key),

    %% 删除数据库
    ?IF(Ti > 0, mud_cache_lib:db_delete(Name, Key)),
    %% 删除定时任务
    ToSave2 = mud_cache_lib:cancel_save(Key, ToSave),
    ToExpire2 = mud_cache_lib:cancel_expire(Key, ToExpire),
    State2 = State#state{
        to_save = ToSave2,
        to_expire = ToExpire2
    },
    State2.


do_expire(Key, now, #state{tbl = Tbl, tbl_idx = TblIdx, save_interval = 0} = State) ->
    %% 缓存是按主键去老化的，所以这里用的是 remove_half_key/2 而不是 sub_half_key/2
    remove_half_key(Key, TblIdx),
    mnesia:dirty_delete(Tbl, Key),
    State;
do_expire(Key, 0, #state{to_expire = ToExpire, invalid_interval = Sec} = State) ->
    ToExpire2 = mud_cache_lib:schedule_expire(Key, Sec, ToExpire),
    State#state{to_expire = ToExpire2};
%% 这里要注意，只要是需要保存的数据，就算sec是0，也要等到下次检查才老化
do_expire(Key, Sec, #state{to_expire = ToExpire} = State) ->
    ToExpire2 = mud_cache_lib:schedule_expire(Key, Sec, ToExpire),
    State#state{to_expire = ToExpire2}.

do_save(_Key, #state{name = Name, save_interval = 0} = State) ->
    ?WARNING("cache ~p cann't save data (no dbase_info config)", [Name]),
    State;
do_save(Key, #state{name = Name, tbl = Tbl, to_save = ToSave} = State) ->
    case mnesia:dirty_read(Tbl, Key) of
        [] ->
            State;
        [#mdv{value = Data}] ->
            %% 保存到数据库
            mud_cache_lib:db_update(Name, Data),
            %% 计划任务里面的可以删掉
            ToSave2 = lists:delete(Key, ToSave),
            State#state{to_save = ToSave2}
    end.


%% 定时任务-保存数据
do_task_save([], _State) -> ok;
do_task_save(ToSave, State) ->
    #state{name = Name} = State,
    Datas = [get_simple_key_from_mnesia(State, Key) || Key <- ToSave],
    Len = erlang:length(Datas),
    ?IF(Len > 0, ?WARNING("~p save ~p datas", [Name, Len])),
    %% 批量更新
    mud_cache_lib:db_update_some(Name, Datas),
    ok.


%% 定时任务-数据老化
do_task_expire([], _State) -> ok;
%% 简单key的老化
do_task_expire(ToExpire, #state{name = Name, tbl = Tbl, tbl_idx = ?undefined}) ->
    Len = erlang:length(ToExpire),
    ?IF(Len > 0, ?WARNING("~p expire ~p datas", [Name, Len])),
    Trans =
        fun() ->
            %% 遍历删除
            lists:foreach(fun(KeyOne) -> mnesia:delete(Tbl, KeyOne, write) end, ToExpire)
        end,
    mnesia:transaction(Trans),  %% {atomic,ok}
    ok;
%% 符合key，按照主键去老化
do_task_expire(ToExpire, #state{name = Name, tbl = Tbl, tbl_idx = TblIdx}) ->
    Len = erlang:length(ToExpire),
    ?IF(Len > 0, ?WARNING("~p expire ~p datas", [Name, Len])),
    Trans =
        fun() ->
            %% 遍历删除
            lists:foreach(
                fun(KeyOne) ->
                    case mnesia:read(TblIdx, KeyOne) of
                        [] ->
                            ?skip;
                        [#mdv{value = KeyTwoList}] ->
                            %% 删除数据
                            lists:foreach(fun(KeyTwo) -> mnesia:delete(Tbl, {KeyOne, KeyTwo}, write) end, KeyTwoList)
                    end,
                    %% 删除索引
                    mnesia:delete(TblIdx, KeyOne, write)
                end, ToExpire)
        end,
    mnesia:transaction(Trans),  %% {atomic,ok}
    ok.


%% 预加载数据
do_preload_datas(#state{tbl_idx = ?undefined} = State) ->  %% 简单数据，直接写入ets
    #state{name = Name, tbl = Tbl} = State,
    %% 读取所有数据
    Datas = mud_cache_lib:db_select_all(Name),
    lists:foreach(
        fun(V) ->
            K = mud_cache_lib:get_key(V, State),
            %% 存入ets
            store_to_mnesia(State, K, V)
        end, Datas),
    Size = mnesia:table_info(Tbl, size),
    ?IF(Size > 10000,
        ?WARNING("cache ~p preload ~p datas and never invalid!!!", [Name, Size]),
        ?NOTICE("cache ~p preload ~p datas and never invalid!!!", [Name, Size])),
    ok;
do_preload_datas(State) ->  %% 复合数据，还要写入key的索引
    #state{name = Name, tbl = Tbl} = State,
    %% 读取所有数据
    Datas = mud_cache_lib:db_select_all(Name),
    KeyMaps =
        lists:foldl(
            fun(V, Kmap) ->
                K = mud_cache_lib:get_key(V, State),
                %% 存入ets
                store_to_mnesia(State, K, V),
                %% 生成索引
                {K1, K2} = K,
                K2ls = maps:get(K1, Kmap, []),
                Kmap#{K1 => [K2 | K2ls]}
            end, #{}, Datas),

    %% 写入索引缓存（上面加载的时候已经把值存了）
    lists:foreach(
        fun({KeyOne, KeyTwoList}) ->
            store_to_mnesia_idx(State, KeyOne, KeyTwoList)
        end, maps:to_list(KeyMaps)),

    Size = ets:info(Tbl, size),
    ?IF(Size > 10000,
        ?WARNING("cache ~p preload ~p datas and never invalid!!!", [Name, Size]),
        ?NOTICE("cache ~p preload ~p datas and never invalid!!!", [Name, Size])),
    ok.


%% 确定mnesia启动
ensure_mnesia_start() ->
    case mnesia:start() of
        ok -> ?skip;
        {error, Reason} -> ?ERROR("mnesia start fail ~p", [Reason])
    end,
    ok.

%% 检查是否已经加入mnesia集群
check_join_mnesia_nodes() ->
    Ns = get_table_nodes(),
    ?WARNING("mnesia nodes ~p", [Ns]),
    case mnesia:system_info(db_nodes) of
        Ns ->
            ?true;
        _ ->
            mnesia:change_config(extra_db_nodes, Ns),
            ?true
    end.


%% 检查表
%% 1、如果表不存在，创建
%% 2、如果表存在，并且字段相同，则加入
%% 3、如果表已经存在，并且字段不同，则自己独立成为节点
check_table(Tbl) ->
    Tables = mnesia:system_info(tables),
    case lists:member(Tbl, Tables) of
        ?true ->
            %% 检查字段
            check_table_fields(Tbl);
        ?false ->
            %% 创建
            create_table(Tbl)
    end,
    ok.


%% 检查字段是否相同
check_table_fields(Tbl) ->
    Fields = record_info(fields, ?DATA_STRUCT),
    case mnesia:table_info(Tbl, attributes) of
        Fields -> check_join_table(Tbl);
        _ -> ok
    end,
    ok.


%% 检查是否加入table的节点
check_join_table(Tbl) ->
    Node = erlang:node(),
    Ls = mnesia:table_info(Tbl, ram_copies),
    case lists:member(Node, Ls) of
        ?true ->
            ?skip;
        ?false ->
            %% 加入
            mnesia:add_table_copy(Tbl, Node, ram_copies),
            %% 等待表可用
            mnesia:wait_for_tables([Tbl], ?SECOND_TO_MS(10))
    end,
    ok.


%% 创建mneisa的表
create_table(Name) ->
    Def = [
        {access_mode, read_write},  %% 可以是 read_only
        {attributes, record_info(fields, ?DATA_STRUCT)}, %% 字段属性
        {ram_copies, [erlang:node()]},   %% 节点列表
        {type, set}  %% 类型固定set
    ],
    %% 必须成功
    {atomic, ok} = mnesia:create_table(Name, Def),
    ok.


%% 获取表格的节点
get_table_nodes() ->
    %% todo 这里看看能优化不
    Group = 1,%%?SERVER_GROUP,
    mud_config:get_env([center, game_nodes, Group], [erlang:node()]).


%% 构建数据表
init_table(TbName) ->
    %% 确保mnesia启动
    ensure_mnesia_start(),
    %% 加入节点
    check_join_mnesia_nodes(),
    check_table(TbName),
    ok.

%% 构建索引表
init_idx_table(TbName) ->
    check_table(TbName),
    ok.

















