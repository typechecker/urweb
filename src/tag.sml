(* Copyright (c) 2008, Adam Chlipala
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

structure Tag :> TAG = struct

open Core

structure U = CoreUtil
structure E = CoreEnv

structure IM = IntBinaryMap
structure SM = BinaryMapFn(struct
                           type ord_key = string
                           val compare = String.compare
                           end)

fun kind (k, s) = (k, s)
fun con (c, s) = (c, s)

fun exp env (e, s) =
    case e of
        EApp (
        (EApp (
         (EApp (
          (ECApp (
           (ECApp (
            (ECApp (
             (ECApp (
              (EFfi ("Basis", "tag"),
               loc), given), _), absent), _), outer), _), inner), _),
          attrs), _),
         tag), _),
        xml) =>
        (case attrs of
             (ERecord xets, _) =>
             let
                 val (xets, s) =
                     ListUtil.foldlMap (fn ((x, e, t), (count, tags, byTag, newTags)) =>
                                           case x of
                                               (CName "Link", _) =>
                                               let
                                                   fun unravel (e, _) =
                                                       case e of
                                                           ENamed n => (n, [])
                                                         | EApp (e1, e2) =>
                                                           let
                                                               val (n, es) = unravel e1
                                                           in
                                                               (n, es @ [e2])
                                                           end
                                                         | _ => (ErrorMsg.errorAt loc "Invalid link expression";
                                                                 (0, []))

                                                   val (f, args) = unravel e

                                                   val (cn, count, tags, newTags) =
                                                       case IM.find (tags, f) of
                                                           NONE =>
                                                           (count, count + 1, IM.insert (tags, f, count),
                                                            (f, count) :: newTags)
                                                         | SOME cn => (cn, count, tags, newTags)

                                                   val (_, _, _, s) = E.lookupENamed env f

                                                   val byTag = case SM.find (byTag, s) of
                                                                   NONE => SM.insert (byTag, s, f)
                                                                 | SOME f' =>
                                                                   (if f = f' then
                                                                       ()
                                                                    else
                                                                        ErrorMsg.errorAt loc 
                                                                                         ("Duplicate HTTP tag "
                                                                                          ^ s);
                                                                    byTag)

                                                   val e = (EClosure (cn, args), loc)
                                                   val t = (CFfi ("Basis", "string"), loc)
                                               in
                                                   (((CName "href", loc), e, t),
                                                    (count, tags, byTag, newTags))
                                               end
                                             | _ => ((x, e, t), (count, tags, byTag, newTags)))
                     s xets
             in
                 (EApp (
                  (EApp (
                   (EApp (
                    (ECApp (
                     (ECApp (
                      (ECApp (
                       (ECApp (
                        (EFfi ("Basis", "tag"),
                         loc), given), loc), absent), loc), outer), loc), inner), loc),
                    (ERecord xets, loc)), loc),
                   tag), loc),
                  xml), s)
             end
           | _ => (ErrorMsg.errorAt loc "Attribute record is too complex";
                   (e, s)))

      | _ => (e, s)

fun decl (d, s) = (d, s)

fun tag file =
    let
        val count = foldl (fn ((d, _), count) =>
                              case d of
                                  DCon (_, n, _, _) => Int.max (n, count)
                                | DVal (_, n, _, _, _) => Int.max (n, count)
                                | DExport _ => count) 0 file

        fun doDecl (d as (d', loc), (env, count, tags, byTag)) =
            case d' of
                DExport n =>
                let
                    val (_, _, _, s) = E.lookupENamed env n
                in
                    case SM.find (byTag, s) of
                        NONE => ([d], (env, count, tags, byTag))
                      | SOME n' => ([], (env, count, tags, byTag))
                end
              | _ =>
                let
                    val (d, (count, tags, byTag, newTags)) =
                        U.Decl.foldMap {kind = kind,
                                        con = con,
                                        exp = exp env,
                                        decl = decl}
                                       (count, tags, byTag, []) d

                    val env = E.declBinds env d

                    val newDs = ListUtil.mapConcat
                                    (fn (f, cn) =>
                                        let
                                            fun unravel (all as (t, _)) =
                                                case t of
                                                    TFun (dom, ran) =>
                                                    let
                                                        val (args, result) = unravel ran
                                                    in
                                                        (dom :: args, result)
                                                    end
                                                  | _ => ([], all)

                                            val (fnam, t, _, tag) = E.lookupENamed env f
                                            val (args, result) = unravel t

                                            val (app, _) = foldl (fn (t, (app, n)) =>
                                                                     ((EApp (app, (ERel n, loc)), loc),
                                                                      n - 1))
                                                                 ((ENamed f, loc), length args - 1) args
                                            val body = (EWrite app, loc)
                                            val unit = (TRecord (CRecord ((KType, loc), []), loc), loc)
                                            val (abs, _, t) = foldr (fn (t, (abs, n, rest)) =>
                                                                        ((EAbs ("x" ^ Int.toString n,
                                                                                t,
                                                                                rest,
                                                                                abs), loc),
                                                                         n + 1,
                                                                         (TFun (t, rest), loc)))
                                                                    (body, 0, unit) args
                                        in
                                            [(DVal ("wrap_" ^ fnam, cn, t, abs, tag), loc),
                                             (DExport cn, loc)]
                                        end) newTags
                in
                    (newDs @ [d], (env, count, tags, byTag))
                end

        val (file, _) = ListUtil.foldlMapConcat doDecl (CoreEnv.empty, count+1, IM.empty, SM.empty) file
    in
        file
    end

end
