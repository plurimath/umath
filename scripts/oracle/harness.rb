# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "yaml"
require_relative "canonical"

module UnicodemathOracle
  PROTOCOL = "unicodemath-oracle/1"
  ROW_SCHEMA = "unicodemath-oracle-row/1"
  REPORT_SCHEMA = "unicodemath-oracle-report/1"
  INVENTORY_SCHEMA = "unicodemath-oracle-inventory/1"

  # Outcomes a worker can report. They are all data about the oracle.
  DATA_OUTCOMES = %w[succeeded refused errored].freeze
  # Outcomes the supervisor assigns when it gets no usable answer. A row with
  # one of these is an incomplete capture, never a refusal.
  INCOMPLETE_OUTCOMES = %w[timed_out crashed].freeze
  OUTCOMES = (DATA_OUTCOMES + INCOMPLETE_OUTCOMES).freeze

  ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

  class Error < StandardError; end

  def self.sha256_file(path)
    Digest::SHA256.file(path).hexdigest
  end

  # Writes a file so that readers see either the old content or the whole new
  # content, never a torn file.
  def self.atomic_write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.tmp-#{Process.pid}"
    File.open(tmp, "wb") do |f|
      f.write(content)
      f.flush
      f.fsync
    end
    File.rename(tmp, path)
  end

  # Loads inventory files and checks that every row id is unique and safe to
  # use as a file name.
  class Inventory
    attr_reader :rows, :files

    def self.load(paths)
      new(paths)
    end

    def initialize(paths)
      raise Error, "no inventory files given" if paths.empty?

      @rows = {}
      @files = []
      duplicates = []
      paths.sort.each do |path|
        doc = YAML.safe_load_file(path)
        unless doc.is_a?(Hash) && doc["schema"] == INVENTORY_SCHEMA
          raise Error, "#{path}: schema must be #{INVENTORY_SCHEMA}"
        end

        @files << { "path" => path, "sha256" => UnicodemathOracle.sha256_file(path),
                    "rows" => Array(doc["rows"]).size }
        Array(doc["rows"]).each do |row|
          row = normalize(row, path)
          duplicates << row["id"] if @rows.key?(row["id"])
          @rows[row["id"]] = row
        end
      end
      return if duplicates.empty?

      raise Error, "duplicate inventory ids: #{duplicates.uniq.sort.join(', ')}"
    end

    def select(ids)
      return @rows.values if ids.nil?

      dupes = ids.tally.select { |_, n| n > 1 }.keys
      raise Error, "duplicate ids requested: #{dupes.join(', ')}" unless dupes.empty?

      missing = ids - @rows.keys
      raise Error, "ids not in inventory: #{missing.join(', ')}" unless missing.empty?

      ids.map { |id| @rows.fetch(id) }
    end

    private

    def normalize(row, path)
      id = row["id"].to_s
      raise Error, "#{path}: bad row id #{row['id'].inspect}" unless id.match?(ID_PATTERN)

      has_text = row.key?("input")
      has_b64 = row.key?("input_base64")
      unless has_text ^ has_b64
        raise Error, "#{path}: row #{id} needs exactly one of input, input_base64"
      end

      input = has_text ? row["input"].to_s : row["input_base64"].unpack1("m0")
      options = row.fetch("options", {}) || {}
      raise Error, "#{path}: row #{id} options must be a mapping" unless options.is_a?(Hash)

      { "id" => id, "input" => input, "options" => options, "source" => path }
    end
  end

  # Runs one worker process with a real monotonic deadline and classifies the
  # result.
  #
  # The worker gets its request on stdin and writes its single JSON result to
  # file descriptor 3. Its stdout and stderr go to log files, so stray output
  # from the oracle can never corrupt the result.
  #
  # Reaching end-of-file on the result pipe does not mean the process has
  # exited: after EOF the supervisor keeps polling the process status until it
  # exits or the same deadline passes. Only the deadline makes a timeout.
  class Supervisor
    KILL_GRACE = 2.0
    POLL = 0.01

    Result = Struct.new(:outcome, :payload, :exitstatus, :termsig, :timed_out,
                        :eof_before_exit, :elapsed, :detail, keyword_init: true)

    def initialize(command:, env: {}, deadline:, log_dir:)
      @command = command
      @env = env
      @deadline = deadline
      @log_dir = log_dir
    end

    def run(id, request)
      FileUtils.mkdir_p(@log_dir)
      req_r, req_w = IO.pipe
      res_r, res_w = IO.pipe
      start = now
      limit = start + @deadline
      pid = spawn_child(id, req_r, res_w)
      req_r.close
      res_w.close
      send_request(req_w, request)

      buffer, eof = read_until_eof(res_r, limit)
      res_r.close
      status = eof ? wait_until(pid, limit) : nil
      eof_before_exit = eof && @saw_running_after_eof
      timed_out = status.nil?
      status = kill(pid) if timed_out

      classify(buffer, status, timed_out, eof_before_exit, now - start)
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def spawn_child(id, req_r, res_w)
      opts = { in: req_r, out: log_path(id, "stdout"), err: log_path(id, "stderr"),
               3 => res_w, pgroup: true, close_others: true }
      Process.spawn(@env, *@command, **opts)
    end

    def log_path(id, stream)
      File.join(@log_dir, "#{id}.#{stream}.log")
    end

    def send_request(io, request)
      io.write(request)
    rescue Errno::EPIPE
      # The child exited before reading; its status tells what happened.
      nil
    ensure
      io.close unless io.closed?
    end

    def read_until_eof(io, limit)
      buffer = +"".b
      loop do
        remaining = limit - now
        return [buffer, false] if remaining <= 0

        next unless io.wait_readable(remaining)

        begin
          buffer << io.read_nonblock(65_536)
        rescue IO::WaitReadable
          next
        rescue EOFError
          return [buffer, true]
        end
      end
    end

    # Polls with WNOHANG. A nil answer means "still running", never "timed
    # out"; the loop only gives up at the deadline.
    def wait_until(pid, limit)
      @saw_running_after_eof = false
      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        @saw_running_after_eof = true
        return nil if now >= limit

        sleep POLL
      end
    end

    def kill(pid)
      signal_group(pid, :TERM)
      grace = now + KILL_GRACE
      while now < grace
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        sleep POLL
      end
      signal_group(pid, :KILL)
      Process.waitpid2(pid).last
    end

    def signal_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    end

    def classify(buffer, status, timed_out, eof_before_exit, elapsed)
      base = { exitstatus: status&.exitstatus, termsig: status&.termsig,
               timed_out: timed_out, eof_before_exit: eof_before_exit,
               elapsed: elapsed }
      if timed_out
        return Result.new(outcome: "timed_out", payload: nil,
                          detail: "no exit within #{@deadline}s", **base)
      end
      if status.signaled? || status.exitstatus != 0
        return Result.new(outcome: "crashed", payload: nil,
                          detail: "worker exit #{status.inspect}", **base)
      end

      payload = parse_payload(buffer)
      if payload.nil?
        return Result.new(outcome: "crashed", payload: nil,
                          detail: "worker exited 0 without a complete result", **base)
      end

      Result.new(outcome: payload["outcome"], payload: payload, detail: nil, **base)
    end

    def parse_payload(buffer)
      payload = JSON.parse(buffer.force_encoding(Encoding::UTF_8), max_nesting: false)
      return nil unless payload.is_a?(Hash)
      return nil unless payload["protocol"] == PROTOCOL
      return nil unless DATA_OUTCOMES.include?(payload["outcome"])

      payload
    rescue JSON::ParserError, EncodingError
      nil
    end
  end

  # Captures a set of inventory rows, one fresh worker process per row, and
  # checkpoints every finished row as its own file. A rerun with the same
  # identity reuses finished data rows and retries incomplete ones.
  class Runner
    def initialize(rows:, out_dir:, supervisor:, identity:, max_attempts: nil)
      @rows = rows
      @out_dir = out_dir
      @supervisor = supervisor
      @identity = identity
      @max_attempts = max_attempts
    end

    def run
      attempted = 0
      reused = 0
      stopped_early = false
      timings = {}
      @rows.each do |row|
        digest = request_digest(row)
        if reusable_row(row["id"], digest)
          reused += 1
          next
        end
        if @max_attempts && attempted >= @max_attempts
          stopped_early = true
          break
        end

        attempted += 1
        result = @supervisor.run(row["id"], JSON.generate(request(row)))
        timings[row["id"]] = { "elapsed" => result.elapsed.round(3),
                               "eof_before_exit" => result.eof_before_exit }
        write_row(row, digest, result)
      end
      summary(attempted, reused, stopped_early, timings)
    end

    def row_path(id)
      File.join(@out_dir, "rows", "#{id}.json")
    end

    private

    def request(row)
      { "protocol" => PROTOCOL, "id" => row["id"],
        "input" => Canonical.string(row["input"]), "options" => row["options"] }
    end

    def request_digest(row)
      Digest::SHA256.hexdigest(JSON.generate([request(row), @identity]))
    end

    def reusable_row(id, digest)
      path = row_path(id)
      return nil unless File.file?(path)

      doc = JSON.parse(File.read(path), max_nesting: false)
      return nil unless doc["request_digest"] == digest
      return nil unless DATA_OUTCOMES.include?(doc["outcome"])

      doc
    rescue JSON::ParserError
      nil
    end

    def write_row(row, digest, result)
      doc = {
        "schema" => ROW_SCHEMA,
        "id" => row["id"],
        "source" => row["source"],
        "request_digest" => digest,
        "outcome" => result.outcome,
        "process" => { "exitstatus" => result.exitstatus, "termsig" => result.termsig },
        "detail" => result.detail,
        "result" => result.payload,
      }
      UnicodemathOracle.atomic_write(row_path(row["id"]), "#{JSON.pretty_generate(doc, max_nesting: false)}\n")
    end

    def summary(attempted, reused, stopped_early, timings)
      expected = @rows.map { |r| r["id"] }
      found = {}
      expected.each do |id|
        path = row_path(id)
        next unless File.file?(path)

        doc = JSON.parse(File.read(path), max_nesting: false)
        found[id] = doc if doc["request_digest"] == request_digest(@rows.find { |r| r["id"] == id })
      end
      counts = OUTCOMES.to_h { |o| [o, found.values.count { |d| d["outcome"] == o }] }
      missing = expected - found.keys
      complete = missing.empty? && INCOMPLETE_OUTCOMES.all? { |o| counts[o].zero? }
      {
        "schema" => REPORT_SCHEMA,
        "identity" => @identity,
        "expected" => expected.size,
        "expected_ids" => expected,
        "attempted_this_run" => attempted,
        "reused" => reused,
        "counts" => counts,
        "rows_found" => found.size,
        "missing" => missing,
        "stopped_early" => stopped_early,
        "complete" => complete,
        "rows" => found.map do |id, doc|
          { "id" => id, "outcome" => doc["outcome"],
            "sha256" => UnicodemathOracle.sha256_file(row_path(id)) }
        end,
        "timings" => timings,
      }
    end
  end
end
