%---------------------------------------------------------------------------%
% mercury_qc.m
%
% Command-line driver for the Mercury circuit compiler.
%
% Usage:
%   mercury_qc check FILE
%       Parse and validate. Diagnostics go to stderr. Exit 0 if the circuit
%       is valid (warnings allowed), 1 otherwise.
%   mercury_qc compile [-O0|-O1] [-o OUT] FILE
%       Parse, validate, optimize (default -O1), and emit OpenQASM 3 to OUT
%       or stdout. Exit 1 and no output on any error.
%   mercury_qc statevector FILE
%       Simulate a unitary circuit and print amplitudes, one per line, as
%       "index re im" with %.15e. Exit 1 on nonunitary input.
%   mercury_qc roundtrip FILE
%       Emit OpenQASM 3, parse that output again, emit again, and require the
%       two emissions to be identical. Exit 1 on mismatch.
%
% Exit codes: 0 success, 1 rejected or failed check, 2 usage or I/O error.
%
%---------------------------------------------------------------------------%

:- module mercury_qc.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module circuit.
:- import_module diagnostic.
:- import_module bool.
:- import_module int.
:- import_module list.
:- import_module maybe.
:- import_module optimize.
:- import_module parser.
:- import_module qasm_emit.
:- import_module statevector.
:- import_module string.
:- import_module validate.

main(!IO) :-
    io.command_line_arguments(Args, !IO),
    dispatch(Args, !IO).

:- pred dispatch(list(string)::in, io::di, io::uo) is det.

dispatch(Args, !IO) :-
    ( if Args = ["check", File] then
        check_file(File, !IO)
    else if Args = ["statevector", File] then
        statevector_file(File, !IO)
    else if Args = ["roundtrip", File] then
        roundtrip_file(File, !IO)
    else if Args = ["compile" | Rest] then
        compile_command(Rest, !IO)
    else
        usage(!IO)
    ).

:- pred usage(io::di, io::uo) is det.

usage(!IO) :-
    io.write_string(io.stderr_stream,
        "usage: mercury_qc check FILE | compile [-O0|-O1] [-o OUT] FILE\n"
        ++ "       mercury_qc statevector FILE | roundtrip FILE\n", !IO),
    io.set_exit_status(2, !IO).

%---------------------------------------------------------------------------%
% Reading

% Read a file, reporting an I/O failure with exit status 2.
:- pred read_source(string::in, maybe_text::out, io::di, io::uo) is det.

:- type maybe_text
    --->    text_ok(string)
    ;       text_err.

read_source(File, Result, !IO) :-
    io.read_named_file_as_string(File, Res, !IO),
    (
        Res = ok(Text),
        Result = text_ok(Text)
    ;
        Res = error(E),
        io.write_string(io.stderr_stream, "mercury-qc: " ++ File ++ ": "
            ++ io.error_message(E) ++ "\n", !IO),
        Result = text_err
    ).

%---------------------------------------------------------------------------%
% Front end: parse, validate, optionally optimize.

:- type front_result
    --->    front_ok(circuit, list(diag))
    ;       front_fail(list(diag)).

% Parse and validate; with Optimize = yes, also run the optimizer.
:- pred front_end(bool::in, string::in, front_result::out) is det.

front_end(Optimize, Text, Result) :-
    parse_program(Text, ParseResult),
    (
        ParseResult = parse_fail(Diags),
        Result = front_fail(Diags)
    ;
        ParseResult = parse_ok(C),
        validate(C, Diags),
        ( if list.any_true(is_error, Diags) then
            Result = front_fail(Diags)
        else if Optimize = yes then
            Result = front_ok(optimize(C), Diags)
        else
            Result = front_ok(C, Diags)
        )
    ).

% Print diagnostics to stderr, one per line.
:- pred report(string::in, list(diag)::in, io::di, io::uo) is det.

report(File, Diags, !IO) :-
    list.foldl(report_one(File), Diags, !IO).

:- pred report_one(string::in, diag::in, io::di, io::uo) is det.

report_one(File, D, !IO) :-
    io.write_string(io.stderr_stream, format_diag(File, D) ++ "\n", !IO).

%---------------------------------------------------------------------------%

:- pred check_file(string::in, io::di, io::uo) is det.

check_file(File, !IO) :-
    read_source(File, Read, !IO),
    (
        Read = text_err,
        io.set_exit_status(2, !IO)
    ;
        Read = text_ok(Text),
        front_end(no, Text, Result),
        (
            Result = front_ok(_, Warnings),
            report(File, Warnings, !IO),
            io.write_string("ok: " ++ File ++ "\n", !IO)
        ;
            Result = front_fail(Diags),
            report(File, Diags, !IO),
            io.set_exit_status(1, !IO)
        )
    ).

%---------------------------------------------------------------------------%

:- pred compile_command(list(string)::in, io::di, io::uo) is det.

compile_command(Args, !IO) :-
    parse_compile_args(Args, Optimize, MaybeOut, MaybeFile),
    ( if MaybeFile = yes(File) then
        read_source(File, Read, !IO),
        (
            Read = text_err,
            io.set_exit_status(2, !IO)
        ;
            Read = text_ok(Text),
            front_end(Optimize, Text, Result),
            (
                Result = front_ok(C, Warnings),
                report(File, Warnings, !IO),
                write_output(MaybeOut, emit_qasm(C), !IO)
            ;
                Result = front_fail(Diags),
                report(File, Diags, !IO),
                io.set_exit_status(1, !IO)
            )
        )
    else
        usage(!IO)
    ).

% Parse compile options. Optimize defaults to yes (-O1).
:- pred parse_compile_args(list(string)::in, bool::out,
    maybe(string)::out, maybe(string)::out) is det.

parse_compile_args(Args, Optimize, Out, File) :-
    parse_compile_args_1(Args, yes, no, no, Optimize, Out, File).

:- pred parse_compile_args_1(list(string)::in, bool::in, maybe(string)::in,
    maybe(string)::in, bool::out, maybe(string)::out, maybe(string)::out)
    is det.

parse_compile_args_1([], Opt, Out, File, Opt, Out, File).
parse_compile_args_1([A | As], Opt0, Out0, File0, Opt, Out, File) :-
    ( if A = "-O0" then
        parse_compile_args_1(As, no, Out0, File0, Opt, Out, File)
    else if A = "-O1" then
        parse_compile_args_1(As, yes, Out0, File0, Opt, Out, File)
    else if A = "-o", As = [Path | Rest] then
        parse_compile_args_1(Rest, Opt0, yes(Path), File0, Opt, Out, File)
    else
        parse_compile_args_1(As, Opt0, Out0, yes(A), Opt, Out, File)
    ).

:- pred write_output(maybe(string)::in, string::in, io::di, io::uo) is det.

write_output(no, Text, !IO) :-
    io.write_string(Text, !IO).
write_output(yes(Path), Text, !IO) :-
    io.open_output(Path, OpenRes, !IO),
    (
        OpenRes = ok(Stream),
        io.write_string(Stream, Text, !IO),
        io.close_output(Stream, !IO)
    ;
        OpenRes = error(E),
        io.write_string(io.stderr_stream, "mercury-qc: " ++ Path ++ ": "
            ++ io.error_message(E) ++ "\n", !IO),
        io.set_exit_status(2, !IO)
    ).

%---------------------------------------------------------------------------%

:- pred statevector_file(string::in, io::di, io::uo) is det.

statevector_file(File, !IO) :-
    read_source(File, Read, !IO),
    (
        Read = text_err,
        io.set_exit_status(2, !IO)
    ;
        Read = text_ok(Text),
        front_end(yes, Text, Result),
        (
            Result = front_fail(Diags),
            report(File, Diags, !IO),
            io.set_exit_status(1, !IO)
        ;
            Result = front_ok(C, _),
            statevector(C, Sv),
            (
                Sv = sv_err(Msg),
                io.write_string(io.stderr_stream, "mercury-qc: " ++ Msg
                    ++ "\n", !IO),
                io.set_exit_status(1, !IO)
            ;
                Sv = sv_ok(Amps),
                print_amplitudes(0, Amps, !IO)
            )
        )
    ).

:- pred print_amplitudes(int::in, list(cpx)::in, io::di, io::uo) is det.

print_amplitudes(_, [], !IO).
print_amplitudes(I, [cpx(Re, Im) | Rest], !IO) :-
    io.format("%d %.15e %.15e\n", [i(I), f(Re), f(Im)], !IO),
    print_amplitudes(I + 1, Rest, !IO).

%---------------------------------------------------------------------------%

:- pred roundtrip_file(string::in, io::di, io::uo) is det.

roundtrip_file(File, !IO) :-
    read_source(File, Read, !IO),
    (
        Read = text_err,
        io.set_exit_status(2, !IO)
    ;
        Read = text_ok(Text),
        front_end(no, Text, First),
        (
            First = front_fail(Diags),
            report(File, Diags, !IO),
            io.set_exit_status(1, !IO)
        ;
            First = front_ok(C1, _),
            Emitted1 = emit_qasm(C1),
            front_end(no, Emitted1, Second),
            (
                Second = front_fail(Diags2),
                report(File, Diags2, !IO),
                io.set_exit_status(1, !IO)
            ;
                Second = front_ok(C2, _),
                Emitted2 = emit_qasm(C2),
                ( if Emitted1 = Emitted2 then
                    io.write_string("roundtrip ok: " ++ File ++ "\n", !IO)
                else
                    io.write_string(io.stderr_stream,
                        "roundtrip mismatch: " ++ File ++ "\n", !IO),
                    io.set_exit_status(1, !IO)
                )
            )
        )
    ).

%---------------------------------------------------------------------------%
:- end_module mercury_qc.
%---------------------------------------------------------------------------%
