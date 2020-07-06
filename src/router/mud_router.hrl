-ifdef(__MUD_ROUTER__).
-define(__MUD_ROUTER__, true).

-define(ETS_ROUTER, ets_mud_router).


-record(routes, {
    cmd = '_',  %% 指令
    rs = []   %% 路由信息，对应one_route
}).

-record(one_route, {
    mfa = '_',    %% {M,F,A}
    ext = '_',    %% 扩展信息
    func = '_', %% fun 格式的mfa
    flag = '_'  %% 标志，目前只有undefined和expired
}).


-endif.
