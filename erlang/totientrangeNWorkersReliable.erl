-module(totientrangeNWorkersReliable).
-export([start_server/0, testRobust/2, server/0, worker/1, watch_worker/3]).

%% TotientRange.erl - Sequential Euler Totient Function (Erlang Version)
%% compile from the shell: >c(totientrange).
%% run from the shell:     >totientrange:sumTotient(1,1000).

%% Phil Trinder 20/10/2018

%% This program calculates the sum of the totients between a lower and an 
%% upper limit. It is based on earlier work by: Nathan Charles, 
%% Hans-Wolfgang Loidl and Colin Runciman

%% The comments provide (executable) Haskell specifications of the functions

%% hcf x 0 = x
%% hcf x y = hcf y (rem x y)

hcf(X,0) -> X;
hcf(X,Y) -> hcf(Y,X rem Y).

%% relprime x y = hcf x y == 1

relprime(X,Y) -> 
  V = hcf(X,Y),
  if 
    V == 1 
      -> true;
    true 
      -> false
  end.

%%euler n = length (filter (relprime n) (mkList n))

euler(N) -> 
  RelprimeN = fun(Y) -> relprime(N,Y) end,  
  length (lists:filter(RelprimeN,(lists:seq(1,N)))).

%% Take completion timestamp, and print elapsed time

printElapsed(S,US) ->
  {_, S2, US2} = os:timestamp(),
                       %% Adjust Seconds if completion Microsecs > start Microsecs
  if
    US2-US < 0 ->
      S3 = S2-1,
      US3 = US2+1000000;
    true ->
      S3 = S2,
      US3 = US2
  end,
  io:format("Server: Time taken in Secs, MicroSecs ~p ~p~n",[S3-S,US3-US]).

workerName(Num) ->
 list_to_atom( "worker" ++ integer_to_list( Num )).

watch_worker(N, Lower, Upper) ->
  process_flag(trap_exit, true),
  Pid = spawn_link(totientrangeNWorkersReliable, worker, [N]),
  register(workerName(N), Pid),
  io:format("Watcher: Watching Worker ~p~n", [workerName(N)]),

  Pid ! {range, Lower, Upper},

  receive
    {'EXIT', Pid, normal} ->
      ok;
    {'EXIT', Pid, _} ->
      watch_worker(N, Lower, Upper);
    finished ->
      Pid ! finished,
      io:format("Watcher Finished ~n")
  end.

worker(N) ->
  receive
    {range, Lower, Upper} ->
      io:format("Worker: Computing Range ~p ~p~n", [Lower, Upper]),
      Res = lists:sum(lists:map(fun euler/1,lists:seq(Lower, Upper))),
      server ! {reply, workerName(N), Res},
      worker(N);
    finished ->
      io:format("Worker: Finished~n"),
      exit(normal)
  end.

get_range(Lower, Upper, NWorkers) ->
  io:format("~p ~p~n", [Lower, Lower+(Upper div NWorkers)*2]),
  if
    Lower+(Upper div NWorkers)*2 > Upper ->
      {Lower, Upper};
    true ->
      {Lower, Lower+(Upper div NWorkers)}
  end.

server() -> 
  receive
    {range, Lower, Upper, NWorkers} ->
      {_, S, US} = os:timestamp(),

      Ranges = [get_range(L, Upper, NWorkers)
                || L <- lists:seq(Lower-1, Upper-1), ((L rem (Upper div NWorkers) == 0) and ((L + (Upper div NWorkers)) =< Upper)) or (L == Lower-1)],             
      Watchers = [ spawn(totientrangeNWorkersReliable, watch_worker, [N, L, U]) || {N, {L, U}} <- lists:zip(lists:seq(1, NWorkers), Ranges)],

      Names = [workerName(N)|| N <- lists:seq(1, NWorkers)],

      Totients = [ receive {reply, Name, Res} -> io:format("Server: Received Sum ~p~n", [Res]), Res end || Name <- Names ],

      [Watcher ! finished || Watcher <- Watchers], 

      Res = lists:sum(Totients),
      io:format("Server: Sum of totients: ~p~n", [Res]),
      printElapsed(S,US),
      server();
    finished ->
      io:format("Server: Finished~n"),
      exit(normal)
  end. 
  
start_server() ->
  register(server,spawn(totientrangeNWorkersReliable,server,[])).

workerChaos(NVictims,NWorkers) ->
  lists:map(
    fun( _ ) ->
      timer:sleep(500), %% Sleep for .5s
      %% Choose a random victim
      WorkerNum = rand:uniform(NWorkers),
      io:format("workerChaos killing ~p~n",
                 [workerName(WorkerNum)]),
      WorkerPid = whereis(workerName(WorkerNum)),
      if %% Check if victim is alive
        WorkerPid == undefined ->
          io:format("workerChaos already dead: ~p~n",
                     [workerName(WorkerNum)]);
        true -> %% Kill Kill Kill
          exit(whereis(workerName(WorkerNum)),chaos)
      end
    end,
    lists:seq( 1, NVictims ) ).

testRobust(NWorkers,NVictims) ->
  ServerPid = whereis(server),
  if ServerPid == undefined ->
      start_server();
    true ->
      ok
  end,
  server ! {range, 1, 15000, NWorkers},
  workerChaos(NVictims,NWorkers).