-ifndef(_MUD_HRL_).
-define(_MUD_HRL_, true).

%% 常用原子
-define(true, true).
-define(false, false).
-define(undefined, undefined).  %% 未定义
-define(indefinitely, indefinitely).  %% 不确定的
-define(continue, continue).   %% 继续
-define(ignore, ignore).  %% 忽略
-define(infinity, infinity).  %% 无穷尽
-define(none, none).  %% 没有
-define(skip, skip).  %% 跳过
-define(disabled, disabled).  %% 关闭
-define(enabled, enabled).  %% 打开

%% 时间
-define(SECONDS_PRE_MIN, 60).
-define(SECONDS_PRE_HOUR, 3600).
-define(SECONDS_PRE_DAY, 86400).
-define(MINUTE2SEC(X), (X * 60)).
-define(HOUR2SEC(X), (X * 3600)).
-define(DAY2SEC(X), (X * 86400)).

-define(SECOND_TO_MS(X), (X * 1000)).
-define(MINUTE_TO_MS(X), (X * 60000)).

%% 条件
-define(IF(C, T), ?IF(C, T, ?skip)).
-define(IF(C, T, F), (case (C) of ?true -> (T);?false -> (F) end)).

%% 字符串
-define(STR(X), (<<X/utf8>>)).


-define(LAGER_TAG(T), ([{tag, T}])).


-define(CRITICAL(F), (lager:critical(F))).
-define(CRITICAL(F, A), (lager:critical(F, A))).
-define(CRITICAL(T, F, A), (lager:critical(?LAGER_TAG(T), F, A))).

-define(ERROR(F), (lager:error(F))).
-define(ERROR(F, A), (lager:error(F, A))).
-define(ERROR(T, F, A), (lager:error(?LAGER_TAG(T), F, A))).

-define(WARNING(F), (lager:warning(F))).
-define(WARNING(F, A), (lager:warning(F, A))).
-define(WARNING(T, F, A), (lager:warning(?LAGER_TAG(T), F, A))).


-define(NOTICE(F), (lager:notice(F))).
-define(NOTICE(F, A), (lager:notice(F, A))).
-define(NOTICE(T, F, A), (lager:notice(?LAGER_TAG(T), F, A))).

-define(INFO(F), (lager:info(F))).
-define(INFO(F, A), (lager:info(F, A))).
-define(INFO(T, F, A), (lager:info(?LAGER_TAG(T), F, A))).

-define(DEBUG(F), (lager:debug(F))).
-define(DEBUG(F, A), (lager:debug(F, A))).
-define(DEBUG(T, F, A), (lager:debug(?LAGER_TAG(T), F, A))).

-define(FOOTMARK, (lager:notice("FOOTMARK >> ~p line:~p", [?MODULE, ?LINE])).


-endif.


