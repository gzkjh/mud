%%%-------------------------------------------------------------------
%%% @author Commando
%%% @copyright (C) 2020, go2mud.com
%%% @doc
%%% 动态编译模块
%%%
%%% ```
%%% 主要用于配置表，或者一些功能性模块的动态生成
%%%
%%% 用法示例：
%%% M = make_module(dt_mod),
%%% E = make_exports([{t0,0},{t1,1},{t2,1},{t3,2}]),
%%% F1 = make_getter_0(t0,123),
%%% F2 = make_getter_1(t1,abc,123),
%%% F3 = make_getter_1(t2,[{a,1},{b,2},{c,3}]),
%%% F4 = make_fun(t3,["Args1","Args2"], {m, f}),
%%% compile(dt_mod, [M, E, F1, F2, F3, F4]). 注意这里的 M,E,F... 不能错
%%%
%%% 生成的结果：
%%% dt_mod:t0()->123.
%%%
%%% dt_mod:t1(abc)->123.
%%%
%%% dt_mod:t2(a)->1;
%%% dt_mod:t2(b)->2;
%%% dt_mod:t2(c)->3;
%%% dt_mod:t2(_)->undefined.
%%%
%%% dt_mod:t3(Args1,Args2)->m:f(Args1,Args2)
%%% '''
%%% @end
%%% Created : 06. 7月 2020 21:26
%%%-------------------------------------------------------------------
-module(mud_dynamic).
-author("Commando").


-include("mud.hrl").


%% API
-export([compile/2, compile/3]).
%% API
-export([make_module/1,
    make_single_export/2, make_exports/1,
    make_getter_0/2, make_getter_1/2, make_getter_1/3,
    make_fun/3, make_fun_ptr/2]).

%% @doc
%% 动态编译模块
%% 相当于 compile(Mod,Forms,[]).
%% @see compile/3
%% @end
-spec compile(atom(), [erl_syntax:syntaxTree()]) -> ok|{error, term()}.
compile(Mod, Forms) -> compile(Mod, Forms, []).


%% @doc
%% 动态编译模块
%% Mod是模块名字，Forms是语法树列表，Opt是编译选项
%% 在动态编译的时候，会先尝试 code:soft_purge(Mod)，如果失败则发出警告信息
%% @end
compile(Mod, Forms, Opts) ->
    Bin = do_compile(Mod, Forms, Opts),
    case code:soft_purge(Mod) of
        ?true ->
            case code:load_binary(Mod, dynamic, Bin) of
                {module, _} ->
                    ok;
                {error, Reason} ->
                    ?ERROR("dynamic compile error ~p", [Reason]),
                    {error, Reason}
            end;
        ?false ->
            ?ERROR("dynamic cann't purge mod ~p", [Mod]),
            {error, soft_purge}
    end.


%% ================================================================================
%% Internal functions
%% ================================================================================

do_compile(Module, Forms, CompileOpts) ->
    Opts = CompileOpts ++ [verbose, warnings_as_errors, report_errors],
    NewForms = [erl_syntax:revert(X) || X <- Forms],
    {ok, Module, Bin} = compile:forms(NewForms, Opts),
    Bin.


%% @doc
%% 构造 -module(Module).
%% @end
-spec make_module(atom()) -> erl_syntax:syntaxTree().
make_module(Module) ->
    erl_syntax:attribute(erl_syntax:atom(module), [erl_syntax:atom(Module)]).


%% @doc
%% 构造单个 -export([FunName/Arity]).
%% @end
-spec make_single_export(atom(), integer()) -> erl_syntax:syntaxTree().
make_single_export(FunName, Arity) ->
    erl_syntax:attribute(erl_syntax:atom(export), [
        erl_syntax:list(erl_syntax:arity_qualifier(erl_syntax:atom(FunName), erl_syntax:integer(Arity)))
    ]).

%% @doc
%% 构造 -export([F1/A1,F2/A2,...Fn/An]).
%% @end
-spec make_exports([{atom(), integer()}]) -> erl_syntax:syntaxTree().
make_exports(List) when is_list(List) ->
    Forms = [erl_syntax:arity_qualifier(erl_syntax:atom(F), erl_syntax:integer(A)) || {F, A} <- List],
    erl_syntax:attribute(erl_syntax:atom(export), [erl_syntax:list(Forms)]).


%% @doc
%% 构造 Fun() -> V 如 get()->123.
%% @end
-spec make_getter_0(atom(), term()) -> erl_syntax:syntaxTree().
make_getter_0(Fun, V) ->
    erl_syntax:function(erl_syntax:atom(Fun),
        [erl_syntax:clause([], none, [erl_syntax:abstract(V)])]).


%% @doc
%% 构造 Fun(K) -> V 如 get(123) -> 456.
%% @end
-spec make_getter_1(atom(), term(), term()) -> erl_syntax:syntaxTree().
make_getter_1(Fun, K, V) ->
    erl_syntax:function(erl_syntax:atom(Fun),
        [erl_syntax:clause([erl_syntax:abstract(K)], none, [erl_syntax:abstract(V)])]).


%% @doc
%% 构造多个 Fun(K) -> V 如 get(123) -> 456.
%% @end
-spec make_getter_1(atom(), term(), term()) -> erl_syntax:syntaxTree().
make_getter_1(Fun, Ls) when is_list(Ls) ->
    Body = [erl_syntax:clause([erl_syntax:abstract(K)], none, [erl_syntax:abstract(V)])
        || {K, V} <- Ls],
    %% 增加一个 Fun(_)->undefined.
    BodyEnd = [erl_syntax:clause([erl_syntax:underscore()], none, [erl_syntax:abstract(?undefined)])],
    Body2 = Body ++ BodyEnd,
    erl_syntax:function(erl_syntax:atom(Fun), Body2).


%% @doc
%% 构造函数 Fun(...Args) -> M:F(...Args).
%% @end
make_fun(Fun, Args, {M, F})
    when is_list(Args) andalso is_atom(M) andalso is_atom(F) ->
    ArgsTree = build_args_syntaxtree(Args), %% 构件参数语法树
    erl_syntax:function(erl_syntax:atom(Fun), [
        erl_syntax:clause(ArgsTree, none, [
            erl_syntax:application(erl_syntax:atom(M), erl_syntax:atom(F), ArgsTree)
        ])
    ]).


%% @private
%% 构件make_fun所需的参数
build_args_syntaxtree(Args) ->
    [erl_syntax:variable(A) || A <- Args].


%% @doc
%% 构造匿名函数 Fun() -> fun M:F/A.
%% @end
-spec make_fun_ptr(atom(), {atom(), atom(), integer()}) -> erl_syntax:syntaxTree().
make_fun_ptr(Fun, {M, F, Arity}) ->
    erl_syntax:function(erl_syntax:atom(Fun), [
        erl_syntax:clause(none, [
            erl_syntax:implicit_fun(erl_syntax:atom(M), erl_syntax:atom(F), erl_syntax:integer(Arity))
        ])
    ]).


%%%% todo 构造复杂的数据结构
%%%% 未测试
%%make_value(V) when is_tuple(V) ->
%%    Vs1 = tuple_to_list(V),
%%    Vs2 = [make_value(Vx) || Vx <- Vs1],
%%    erl_syntax:tuple(Vs2);
%%make_value(V) when is_list(V) ->
%%    Vs = [make_value(Vx) || Vx <- V],
%%    erl_syntax:list(Vs);
%%make_value(V) when is_map(V) ->
%%    Ls1 = maps:to_list(V),
%%    Ls2 = lists:foldl(
%%        fun({Key, Value}, Acc) ->
%%            Vx = erl_syntax:map_field_assoc(make_value(Key), make_value(Value)),
%%            [Vx | Acc]
%%        end, [], Ls1),
%%    erl_syntax:map_expr(Ls2);
%%make_value(V) ->
%%    erl_syntax:abstract(V).























