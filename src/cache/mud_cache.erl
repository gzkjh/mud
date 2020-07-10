%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 10. 7月 2020 19:52
%%%-------------------------------------------------------------------
-module(mud_cache).
-author("Commando").

-include("mud_cache.hrl").
-include("mud.hrl").

%% API
-export([start/0, stop/0]).


-export([new/2]).



new(Name, Opts) ->
    new(ets, Name, Opts).


new(ets, Name, Opts) ->
    ChildSpec = #{
        id => Name,
        start => {mud_cache_ets_worker, start_link, [Name, Opts]},
        restart => permanent,
        shutdown => 2000,
        type => worker,
        modules => [mud_cache_ets_worker]
    },
    supervisor:start_child(mud_cache_sup, ChildSpec);
new(mnesia, Name, Opts) ->
    ChildSpec = #{
        id => Name,
        start => {mud_cache_mnesia_worker, start_link, [Name, Opts]},
        restart => permanent,
        shutdown => 2000,
        type => worker,
        modules => [mud_cache_mnesia_worker]
    },
    supervisor:start_child(mud_cache_sup, ChildSpec).



lookup(Name, Key) ->
    lookup(Name, Key, ?undefined).


lookup(Name, Key, Default) ->
    TabName = mud_cache_lib:get_table_name(Name),
    case ets:lookup(TabName, Key) of
        [#mdv{value = Data1}] ->
            Data1;
        [{_, Data1}] ->
            Data1;
        [] ->
            case gen_server:call(TabName, {lookup, Key}) of
                ?undefined -> Default;
                Data2 -> Data2
            end
    end.




list_all_cached(Name) ->
    TabName = mud_cache_lib:get_table_name(Name),
    %% ets 的keypos是1，mnesia的keypos是2，暂时用这个来判断
    case ets:info(TabName, keypos) of
        1 -> mud_cache_ets:list_all_cached(Name);
        2 -> mud_cache_mnesia:list_all_cached(Name)
    end.

list_all_cached_keys(Name) ->
    L = list_all_cached(Name),
    [K || {K, _V} <- L].


list_all_cached_values(Name) ->
    L = list_all_cached(Name),
    [V || {_K, V} <- L].


insert(Name, Value) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! {insert, Value},
    ok.


sync_insert(Name, Value) ->
    TabName = mud_cache_lib:get_table_name(Name),
    gen_server:call(TabName, {insert, Value}).



update(Name, Value) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! {update, Value},
    ok.


sync_update(Name, Value) ->
    TabName = mud_cache_lib:get_table_name(Name),
    gen_server:call(TabName, {update, Value}).

expire(Name, Key) -> expire(Name, Key, 0).


expire(Name, Key, Sec) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! {expire, Key, Sec},
    ok.


delete(Name, Key) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! {delete, Key},
    ok.


sync_delete(Name, Key) ->
    TabName = mud_cache_lib:get_table_name(Name),
    gen_server:call(TabName, {delete, Key}).




save(Name, Key) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! {save, Key},
    ok.


save_all(Name) ->
    TabName = mud_cache_lib:get_table_name(Name),
    TabName ! save_all,
    ok.


start() ->
    Child = #{
        id => mud_cache_sup,
        start => {mud_cache_sup, start_link, []},
        shutdown => 5000,
        type => supervisor,
        modules => [mud_cache_sup]
    },
    {ok, _} = supervisor:start_child(mud_sup, Child),
    ok.


stop() ->
    %% 先关闭cache
    mud_cache_sup:stop(),
    supervisor:terminate_child(mud_sup, ms_cache_sup),
    ?WARNING("Closeing ~p Now...", [?MODULE]),
    timer:sleep(1000),
    ok.




%%% =======================================================
%%% internal functions
%%% =======================================================

































