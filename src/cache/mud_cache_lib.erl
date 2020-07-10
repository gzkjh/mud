%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 10. 7月 2020 20:11
%%%-------------------------------------------------------------------
-module(mud_cache_lib).
-author("Commando").


-include("mud_cache.hrl").
-include("mud.hrl").


%% API
-export([make_table_name/1, get_table_name/1, make_idx_table_name/1, get_key/2,
    db_select_all/1, db_select/2, db_select/3,
    db_insert/2, db_update/2, db_update_some/2, db_delete/2,
    schedule_save/3, schedule_expire/3, cancel_expire/2,
    analyze_expire/1, schedule_task/2]).


%% 创建表名字
make_table_name(Name) when is_atom(Name) ->
    list_to_atom(?PREFIX ++ atom_to_list(Name)).
%% 获取表名字
get_table_name(Name) when is_atom(Name) ->
    list_to_existing_atom(?PREFIX ++ atom_to_list(Name)).

make_idx_table_name(Name) when is_atom(Name) ->
    list_to_atom(?PREFIX ++ atom_to_list(Name) ++ ?TAB_HALF_KEY).


%% 复合主键
get_key(Value, #state{keypos = {I1, I2}}) when is_tuple(Value) ->
    K1 = erlang:element(I1, Value),
    K2 = erlang:element(I2, Value),
    {K1, K2};
get_key(Value, #state{keypos = {I1, I2}}) when is_map(Value) ->
    K1 = maps:get(I1, Value),
    K2 = maps:get(I2, Value),
    {K1, K2};
%% 简单主键
get_key(Value, #state{keypos = Idx}) when is_tuple(Value) ->
    erlang:element(Idx, Value);
get_key(Value, #state{keypos = Idx}) when is_map(Value) ->
    maps:get(Idx, Value).



get_invalid_time(0) -> 0;
get_invalid_time(Sec) ->
    mud_calendar:timestamp() + Sec.


%% 更新计划任务（数据保存和数据老化）
schedule_task(_Key, State = #state{save_interval = 0, invalid_interval = 0}) ->
    %% 既不保存，也不老化
    State;
schedule_task(Key, State) ->
    #state{
        save_interval = TiSave,
        invalid_interval = TiExpire,
        to_save = ToSave,
        to_expire = ToExpire
    } = State,
    ToSave2 = schedule_save(Key, TiSave, ToSave),
    ToExpire2 = schedule_expire(Key, TiExpire, ToExpire),
    State#state{
        to_save = ToSave2,
        to_expire = ToExpire2
    }.


%% 保存
schedule_save(_Key, 0, _SaveList) ->
    [];
schedule_save(Key, _Ti, SaveList) ->
    case lists:member(Key, SaveList) of
        ?true -> SaveList;
        ?false -> [Key | SaveList]
    end.

%% 老化
schedule_expire(_Key, 0, ToExpire) ->
    ToExpire;
schedule_expire({KeyOne, _KeyTwo}, Ti, ToExpire) ->
    %% 复合主键，按照第一个键去老化
    schedule_expire(KeyOne, Ti, ToExpire);
schedule_expire(Key, Ti, ToExpire) ->
    Ti2 = get_invalid_time(Ti),
    ToExpire#{Key => Ti2}.

cancel_expire({KeyOne, _KeyTwo}, ToExpire) ->
    cancel_expire(KeyOne, ToExpire);
cancel_expire(Key, ToExpire) ->
    maps:remove(Key, ToExpire).


analyze_expire(ToExpire) ->
    Ti = mud_calendar:timestamp(),
    maps:fold(
        fun
            (K, V, {Keep, UnKeep}) when V > Ti -> {Keep#{K => V}, UnKeep};    %% 还没过期，保留
            (K, _V, {Keep, UnKeep}) -> {Keep, [K | UnKeep]}    %% 还没过期，保留
        end,
        {#{}, []}, ToExpire).


%% 数据库操作
db_select_all(Name) ->
    try mud_dbase:select_all_terms(Name)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache select all false ~p", [Name, Reason]),
            []
    end.

db_select(Name, Key) ->
    try mud_dbase:select_term(Name, Key)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache select ~p false ~p", [Name, Key, Reason]),
            []
    end.

db_select(Name, Index, Key) ->
    try mud_dbase:select_term(Name, Index, Key)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache select ~p by index ~p false ~p", [Name, Key, Index, Reason]),
            []
    end.

db_insert(Name, Data) ->
    try mud_dbase:insert_term(Name, Data)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache insert ~p false ~p", [Name, Data, Reason]),
            ok
    end.

db_update(Name, Data) ->
    try mud_dbase:update_term(Name, Data)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache update ~p false ~p", [Name, Data, Reason]),
            ok
    end.

db_update_some(Name, Datas) ->
    try mud_dbase:update_terms(Name, Datas)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache update some ~p false ~p", [Name, Datas, Reason]),
            ok
    end.
db_delete(Name, Key) ->
    try mud_dbase:delete_term(Name, Key)
    catch
        _:Reason:_Stack ->
            ?ERROR("~p cache deletet ~p false ~p", [Name, Key, Reason]),
            ok
    end.

























