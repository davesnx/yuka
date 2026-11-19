let answer n = Printf.sprintf "server-only-answer-%d-pid-%b" (n * 2) (Unix.getpid () > 0)
