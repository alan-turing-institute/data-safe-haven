from data_safe_haven.commands import application


class TestHelp:
    def result_checker(self, result):
        assert result.exit_code == 0
        assert "Usage: dsh [OPTIONS] COMMAND [ARGS]..." in result.stdout
        assert "Arguments to the main executable" in result.stdout
        assert "│ --output" in result.stdout
        assert "│ --verbosity" in result.stdout
        assert "│ --version" in result.stdout
        assert "│ --install-completion" in result.stdout
        assert "│ --show-completion" in result.stdout
        assert "│ --help" in result.stdout
        assert "│ admin" in result.stdout
        assert "│ config" in result.stdout
        assert "│ context" in result.stdout
        assert "│ deploy" in result.stdout
        assert "│ teardown" in result.stdout

    def test_help(self, runner):
        result = runner.invoke(application, ["--help"])
        self.result_checker(result)

    def test_help_short_code(self, runner):
        result = runner.invoke(application, ["-h"])
        self.result_checker(result)
