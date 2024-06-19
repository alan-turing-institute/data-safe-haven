from data_safe_haven.commands import application
from data_safe_haven.version import __version__


class TestHelp:
    def result_checker(self, result):
        assert result.exit_code == 0
        assert "Usage: dsh [OPTIONS] COMMAND [ARGS]..." in result.stdout
        assert "Arguments to the main executable" in result.stdout
        assert "│ --verbose" in result.stdout
        assert "│ --show-level" in result.stdout
        assert "│ --version" in result.stdout
        assert "│ --install-completion" in result.stdout
        assert "│ --show-completion" in result.stdout
        assert "│ --help" in result.stdout
        assert "│ users" in result.stdout
        assert "│ config" in result.stdout
        assert "│ context" in result.stdout
        assert "│ shm" in result.stdout
        assert "│ sre" in result.stdout

    def test_help(self, runner):
        result = runner.invoke(application, ["--help"])
        self.result_checker(result)

    def test_help_short_code(self, runner):
        result = runner.invoke(application, ["-h"])
        self.result_checker(result)


class TestVersion:
    def test_version(self, runner):
        result = runner.invoke(application, ["--version"])
        assert result.exit_code == 0
        assert f"Data Safe Haven {__version__}" in result.stdout
