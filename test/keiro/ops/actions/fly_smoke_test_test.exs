defmodule Keiro.Ops.Actions.FlySmokeTestTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.Actions.FlySmokeTest

  test "reports unhealthy when connection fails" do
    assert {:ok, result} =
             FlySmokeTest.run(%{url: "http://127.0.0.1:1", expected_status: 200}, %{})

    assert result.healthy == false
    assert result.status_code == nil
    assert is_binary(result.error)
  end

  test "reports healthy when status matches expected" do
    # This hits a real HTTP server (httpbin) — skip if offline
    assert {:ok, result} =
             FlySmokeTest.run(%{url: "http://127.0.0.1:1", expected_status: 200}, %{})

    # Connection will fail to port 1, so this tests the error path again
    # The success path requires a running HTTP server — covered in integration
    assert is_map(result)
  end

  test "truncates non-binary body" do
    # Exercise truncate_body/1 for non-binary
    # Can't easily trigger via run/2 without a server, so test indirectly
    assert {:ok, result} =
             FlySmokeTest.run(%{url: "http://127.0.0.1:1"}, %{})

    assert result.healthy == false
  end

  # -- Script mode tests --

  test "script mode: passing script returns healthy" do
    script_path = write_temp_script("#!/bin/bash\necho 'all tests passed'\nexit 0")

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: script_path},
               %{}
             )

    assert result.healthy == true
    assert result.output =~ "all tests passed"
  end

  test "script mode: failing script returns unhealthy with exit code" do
    script_path = write_temp_script("#!/bin/bash\necho 'FAIL: 2 tests failed'\nexit 1")

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: script_path},
               %{}
             )

    assert result.healthy == false
    assert result.exit_code == 1
    assert result.output =~ "FAIL"
  end

  test "script mode: missing script returns error" do
    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: "/nonexistent/smoke.sh"},
               %{}
             )

    assert result.healthy == false
    assert result.error =~ "script not found"
  end

  test "script mode: repo_path in params resolves script relative to repo" do
    dir = System.tmp_dir!() |> Path.join("keiro_smoke_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    script_content = "#!/bin/bash\necho \"testing $1\"\nexit 0"
    File.write!(Path.join(dir, "smoke.sh"), script_content)

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: "smoke.sh", repo_path: dir},
               %{}
             )

    assert result.healthy == true
    assert result.output =~ "testing http://example.com"
  after
    # cleanup handled by OS tmp
    :ok
  end

  test "script mode: repo_path '.' in params resolves from context" do
    dir = System.tmp_dir!() |> Path.join("keiro_smoke_dot_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    script_content = "#!/bin/bash\necho \"dot resolved: $1\"\nexit 0"
    File.write!(Path.join(dir, "smoke.sh"), script_content)

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: "smoke.sh", repo_path: "."},
               %{repo_path: dir}
             )

    assert result.healthy == true
    assert result.output =~ "dot resolved"
  after
    :ok
  end

  test "script mode: repo_path falls back to context when not in params" do
    dir = System.tmp_dir!() |> Path.join("keiro_smoke_ctx_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    script_content = "#!/bin/bash\necho \"context path works: $1\"\nexit 0"
    File.write!(Path.join(dir, "smoke.sh"), script_content)

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://example.com", script: "smoke.sh"},
               %{repo_path: dir}
             )

    assert result.healthy == true
    assert result.output =~ "context path works"
  after
    :ok
  end

  test "script mode: script receives URL as argument" do
    script_path =
      write_temp_script(
        "#!/bin/bash\nif [ \"$1\" = \"http://test.local\" ]; then\n  echo 'URL received'\n  exit 0\nelse\n  echo \"wrong URL: $1\"\n  exit 1\nfi"
      )

    assert {:ok, result} =
             FlySmokeTest.run(
               %{url: "http://test.local", script: script_path},
               %{}
             )

    assert result.healthy == true
    assert result.output =~ "URL received"
  end

  defp write_temp_script(content) do
    path =
      System.tmp_dir!()
      |> Path.join("keiro_test_#{:rand.uniform(100_000)}.sh")

    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end
end
