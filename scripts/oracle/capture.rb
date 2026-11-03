# frozen_string_literal: true

# Captures legacy Plurimath UnicodeMath behaviour for inventory rows.
#
#   bundle exec ruby scripts/oracle/capture.rb --oracle PLURIMATH_CHECKOUT \
#     [--ids id1,id2] [--inventory FILE ...] [--out DIR] [--report FILE] \
#     [--deadline SECONDS] [--max-attempts N]
#
# PLURIMATH_CHECKOUT must be a clean checkout of plurimath/plurimath at
# ORACLE_COMMIT. Each row runs in a fresh worker process inside the oracle
# bundle described by scripts/oracle/Gemfile and Gemfile.lock; set
# ORACLE_BUNDLE_PATH if that bundle is not installed in vendor/oracle-bundle.
#
# Exit status: 0 when every selected row has a data outcome (succeeded,
# refused or errored), 2 when any row is missing, timed out or crashed,
# 1 on usage or setup errors.
#
# --worker replaces the legacy worker with another script. It exists for the
# harness specs, which use a fake worker instead of Plurimath.

require "optparse"
require "rbconfig"
require_relative "harness"

module UnicodemathOracle
  ORACLE_REPOSITORY = "https://github.com/plurimath/plurimath"
  ORACLE_COMMIT = "e7ab4a5186c9be96f62d670574bc2c72f9365ad4"
  ROOT = File.expand_path("../..", __dir__)
  ORACLE_DIR = File.join(ROOT, "scripts", "oracle")
  LEGACY_WORKER = File.join(ORACLE_DIR, "worker.rb")
  HARNESS_FILES = %w[capture.rb harness.rb canonical.rb worker.rb Gemfile Gemfile.lock].freeze

  class CLI
    def initialize(argv)
      @options = {
        inventory: Dir[File.join(ROOT, "corpora", "oracle", "inventory", "*.yml")],
        deadline: 300.0,
        out: File.join(ROOT, "tmp", "oracle-capture"),
      }
      parse(argv)
    end

    def run
      rows = Inventory.load(@options[:inventory]).select(@options[:ids])
                      .map { |r| r.merge("source" => relative(r["source"])) }
      command, env = worker_command
      out = @options[:out]
      supervisor = Supervisor.new(command: command, env: env, deadline: @options[:deadline],
                                  log_dir: File.join(out, "logs"))
      runner = Runner.new(rows: rows, out_dir: out, supervisor: supervisor,
                          identity: identity, max_attempts: @options[:max_attempts])
      report = runner.run
      report["inventory"] = Inventory.load(@options[:inventory]).files.map do |f|
        f.merge("path" => relative(f["path"]))
      end
      report["out_dir"] = relative(out)
      report["deadline"] = @options[:deadline]
      report_path = @options[:report] || File.join(out, "report.json")
      UnicodemathOracle.atomic_write(report_path, "#{JSON.pretty_generate(report)}\n")
      warn summary_line(report, report_path)
      report["complete"] ? 0 : 2
    rescue Error => e
      warn "capture: #{e.message}"
      1
    end

    private

    def parse(argv)
      OptionParser.new do |o|
        o.on("--oracle DIR") { |v| @options[:oracle] = File.expand_path(v) }
        o.on("--ids LIST") { |v| @options[:ids] = v.split(",").map(&:strip) }
        o.on("--inventory FILE") do |v|
          (@options[:explicit_inventory] ||= []) << File.expand_path(v)
          @options[:inventory] = @options[:explicit_inventory]
        end
        o.on("--out DIR") { |v| @options[:out] = File.expand_path(v) }
        o.on("--report FILE") { |v| @options[:report] = File.expand_path(v) }
        o.on("--deadline SECONDS", Float) { |v| @options[:deadline] = v }
        o.on("--max-attempts N", Integer) { |v| @options[:max_attempts] = v }
        o.on("--worker FILE") { |v| @options[:worker] = File.expand_path(v) }
      end.parse!(argv)
    end

    def worker_command
      if @options[:worker]
        return [[RbConfig.ruby, @options[:worker]], clean_env({})]
      end

      oracle = @options[:oracle] or raise Error, "--oracle is required"
      verify_oracle(oracle)
      env = { "BUNDLE_GEMFILE" => File.join(ORACLE_DIR, "Gemfile"),
              "BUNDLE_PATH" => ENV.fetch("ORACLE_BUNDLE_PATH",
                                         File.join(ROOT, "vendor", "oracle-bundle")),
              "BUNDLE_FROZEN" => "true" }
      [[RbConfig.ruby, "-I", File.join(oracle, "lib"), "-rbundler/setup", LEGACY_WORKER],
       clean_env(env)]
    end

    # Drops the variables `bundle exec` sets for the harness bundle so the
    # worker loads only the oracle bundle.
    def clean_env(extra)
      cleared = ENV.keys.grep(/\A(BUNDLE_|BUNDLER_|RUBYOPT\z|RUBYLIB\z|GEM_HOME\z|GEM_PATH\z)/)
      cleared.to_h { |k| [k, nil] }.merge(extra)
    end

    def verify_oracle(dir)
      head = git(dir, "rev-parse", "HEAD")
      unless head == ORACLE_COMMIT
        raise Error, "oracle checkout #{dir} is at #{head}, expected #{ORACLE_COMMIT}"
      end
      dirty = git(dir, "status", "--porcelain", "--untracked-files=no")
      raise Error, "oracle checkout #{dir} has local changes" unless dirty.empty?
    end

    def git(dir, *args)
      out = IO.popen(["git", "-C", dir, *args], err: File::NULL, &:read).to_s.strip
      raise Error, "git #{args.join(' ')} failed in #{dir}" unless $?.success?

      out
    end

    def identity
      files = HARNESS_FILES.to_h do |name|
        [name, UnicodemathOracle.sha256_file(File.join(ORACLE_DIR, name))]
      end
      worker = @options[:worker]
      {
        "oracle" => worker ? nil : { "repository" => ORACLE_REPOSITORY, "commit" => ORACLE_COMMIT },
        "worker" => worker ? { "path" => relative(worker),
                               "sha256" => UnicodemathOracle.sha256_file(worker) } : "legacy",
        "harness_sha256" => files,
        "ruby" => RUBY_VERSION,
      }
    end

    def relative(path)
      path.start_with?("#{ROOT}/") ? path.delete_prefix("#{ROOT}/") : path
    end

    def summary_line(report, path)
      counts = report["counts"].map { |k, v| "#{k}=#{v}" }.join(" ")
      "capture: expected=#{report['expected']} #{counts} missing=#{report['missing'].size} " \
        "complete=#{report['complete']} report=#{path}"
    end
  end
end

exit UnicodemathOracle::CLI.new(ARGV).run if $PROGRAM_NAME == __FILE__
