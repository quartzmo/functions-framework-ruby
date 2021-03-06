# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helper"

require "net/http"
require "uri"

require "functions_framework/cli"

describe FunctionsFramework::CLI do
  let(:http_source) { File.join __dir__, "function_definitions", "simple_http.rb" }
  let(:event_source) { File.join __dir__, "function_definitions", "simple_event.rb" }
  let(:retry_count) { 10 }
  let(:retry_interval) { 0.5 }
  let(:port) { "8066" }

  def run_with_retry cli
    server = cli.start_server
    begin
      last_error = nil
      retry_count.times do
        begin
          return yield
        rescue ::SystemCallError => e
          last_error = e
        end
      end
      raise last_error
    ensure
      server.stop.wait_until_stopped timeout: 10
    end
  end

  before do
    @saved_registry = FunctionsFramework.global_registry
    FunctionsFramework.global_registry = FunctionsFramework::Registry.new
    @saved_level = FunctionsFramework.logger.level
  end

  after do
    FunctionsFramework.global_registry = @saved_registry
    FunctionsFramework.logger.level = @saved_level
    ENV["FUNCTION_TARGET"] = nil
    ENV["FUNCTION_SOURCE"] = nil
    ENV["FUNCTION_SIGNATURE_TYPE"] = nil
  end

  it "runs an http server" do
    args = [
      "--source", http_source,
      "--target", "simple-http",
      "--port", port,
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    response = run_with_retry cli do
      Net::HTTP.get_response URI("http://127.0.0.1:#{port}/")
    end
    assert_equal "200", response.code
    assert_equal "I received a request: GET http://127.0.0.1:#{port}/", response.body
  end

  it "succeeds the signature type check for an http server" do
    args = [
      "--source", http_source,
      "--target", "simple-http",
      "--port", port,
      "--signature-type", "http",
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    run_with_retry cli do
    end
  end

  it "fails the signature type check for an http server" do
    args = [
      "--source", http_source,
      "--target", "simple-http",
      "--port", port,
      "--signature-type", "cloudevent",
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    error = assert_raises(RuntimeError) do
      run_with_retry cli do
      end
    end
    assert_match(/Function "simple-http" does not match type cloudevent/, error.message)
  end

  it "succeeds the signature type check for an event server" do
    args = [
      "--source", event_source,
      "--target", "simple-event",
      "--port", port,
      "--signature-type", "cloudevent",
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    run_with_retry cli do
    end
  end

  it "succeeds the signature type check for a legacy event server" do
    args = [
      "--source", event_source,
      "--target", "simple-event",
      "--port", port,
      "--signature-type", "event",
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    run_with_retry cli do
    end
  end

  it "fails the signature type check for an event server" do
    args = [
      "--source", event_source,
      "--target", "simple-event",
      "--port", port,
      "--signature-type", "http",
      "-q"
    ]
    cli = FunctionsFramework::CLI.new.parse_args args
    error = assert_raises(RuntimeError) do
      run_with_retry cli do
      end
    end
    assert_match(/Function "simple-event" does not match type http/, error.message)
  end
end
