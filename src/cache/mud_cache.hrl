%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%%
%%% @end
%%% Created : 10. 7月 2020 19:45
%%%-------------------------------------------------------------------
-author("Commando").


-ifdef(__MUD_CACHE_HRL__).
-define(__MUD_CACHE_HRL__, true).


%% ets前缀，同时也是进程名字前缀
-define(PREFIX, "mud_cache_").

%% 索引表
-define(TAB_HALF_KEY, "_half_key").

-record(state, {
    name :: atom(),                   %% 组件名字
    tbl :: atom(),                    %% 表名字
    tbl_idx :: atom(),                %% 记录表
    keypos :: integer()|tuple(),      %% 键值
    save_interval :: integer(),       %% 保存时间，如果是0，表示不保存
    invalid_interval :: integer(),    %% 失效时间
    loop_timeout :: integer(),        %% 定时器循环
    to_save = [] :: list(),           %% 计划保存的key
    to_expire = #{} :: map()          %% 计划删除的key
}).


%% mdv的意思是 mnesia data value
-define(DATA_STRUCT, mdv).
-record(mdv, {
    key :: atom(),    %% 键
    value :: term()   %% 数据
}).



-endif.
