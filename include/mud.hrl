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


-endif.


