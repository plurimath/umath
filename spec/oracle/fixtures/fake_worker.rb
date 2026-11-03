# frozen_string_literal: true

# Stand-in for scripts/oracle/worker.rb used by the harness specs. The row
# input is a command that makes it behave like a well-behaved, slow, hung or
# crashing oracle. It speaks the same protocol as the real worker.

require "json"

PROTOCOL = "unicodemath-oracle/1"

request = JSON.parse($stdin.read)
command = request.dig("input", "v").to_s
result_io = IO.for_fd(3, "wb")

def result(request, outcome)
  JSON.generate("protocol" => PROTOCOL, "id" => request["id"], "outcome" => outcome,
                "boundaries" => { "input" => request["input"] })
end

case command
when "ok"
  result_io.write(result(request, "succeeded"))
when "refuse"
  result_io.write(result(request, "refused"))
when "error"
  result_io.write(result(request, "errored"))
when /\Asleep:(\d+(?:\.\d+)?)\z/
  # Hangs before answering: a real deadline expiry.
  sleep Float(Regexp.last_match(1))
  result_io.write(result(request, "succeeded"))
when "crash-signal"
  Process.kill(:KILL, Process.pid)
when "crash-exit"
  $stdout.puts "about to fail"
  exit!(3)
when "partial"
  result_io.write(result(request, "succeeded")[0, 20])
when "bad-outcome"
  result_io.write(JSON.generate("protocol" => PROTOCOL, "outcome" => "timed_out"))
when /\Aeof-then-exit:(\d+(?:\.\d+)?)\z/
  # Answers and closes the pipe, then keeps running for a while before a
  # clean exit. EOF before exit must not be mistaken for a timeout.
  result_io.write(result(request, "succeeded"))
  result_io.close
  sleep Float(Regexp.last_match(1))
  exit 0
when /\Aeof-then-hang:(\d+(?:\.\d+)?)\z/
  result_io.write(result(request, "succeeded"))
  result_io.close
  sleep Float(Regexp.last_match(1))
when "close-without-result"
  result_io.close
else
  warn "unknown fake command #{command.inspect}"
  exit!(4)
end
result_io.close unless result_io.closed?
