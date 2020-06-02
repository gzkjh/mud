%%%-------------------------------------------------------------------
%% @doc mud public API
%% @end
%%%-------------------------------------------------------------------

-module(mud_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    mud_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
