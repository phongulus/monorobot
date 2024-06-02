open Common
open Devkit

let log = Log.from "state"

type t = { state : State_t.state }

let empty_repo_state () : State_t.repo_state = { pipeline_statuses = StringMap.empty }

let empty () : t =
  let state = State_t.{ repos = Stringtbl.empty (); bot_user_id = None } in
  { state }

let find_or_add_repo' state repo_url =
  match Stringtbl.find_opt state.State_t.repos repo_url with
  | Some repo -> repo
  | None ->
    let new_repo = empty_repo_state () in
    Stringtbl.add state.State_t.repos repo_url new_repo;
    new_repo

let set_repo_state { state } repo_url repo_state = Stringtbl.replace state.repos repo_url repo_state
let find_or_add_repo { state } repo_url = find_or_add_repo' state repo_url

let set_repo_pipeline_status { state } repo_url ~pipeline ~(branches : Github_t.branch list) ~status =
  let set_branch_status branch_statuses =
    let new_statuses = List.map (fun (b : Github_t.branch) -> b.name, status) branches in
    let init = Option.default StringMap.empty branch_statuses in
    Some (List.fold_left (fun m (key, data) -> StringMap.add key data m) init new_statuses)
  in
  let repo_state = find_or_add_repo' state repo_url in
  repo_state.pipeline_statuses <- StringMap.update pipeline set_branch_status repo_state.pipeline_statuses

let set_bot_user_id { state; _ } user_id = state.State_t.bot_user_id <- Some user_id
let get_bot_user_id { state; _ } = state.State_t.bot_user_id

let save { state; _ } path =
  let data = State_j.string_of_state state |> Yojson.Basic.from_string |> Yojson.Basic.pretty_to_string in
  try
    Files.save_as path (fun oc -> output_string oc data);
    Ok ()
  with exn -> fmt_error ~exn "failed to save state to file %s" path

module In_memory = struct
  module Dm_commits = struct
    let state = ref (StringSet.empty, StringSet.empty)
    let rotation_threshold = 1000

    let add (sha : string) =
      let s1, s2 = !state in
      let s1 = StringSet.add sha s1 in
      let s1, s2 = if StringSet.cardinal s1 > rotation_threshold then StringSet.empty, s1 else s1, s2 in
      state := s1, s2

    let mem (sha : string) =
      let s1, s2 = !state in
      StringSet.mem sha s1 || StringSet.mem sha s2
  end
end
