from data_safe_haven.commands.context import context_command_group


class TestShow:
    def test_show(self, runner):
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Current context: acmedeployment" in result.stdout
        assert "Description: Acme Deployment" in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Current context: None" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["show"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestAvailable:
    def test_available(self, runner):
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acmedeployment*" in result.stdout
        assert "gems" in result.stdout

    def test_available_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acmedeployment" in result.stdout
        assert "gems" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["available"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestSwitch:
    def test_switch(self, runner):
        result = runner.invoke(context_command_group, ["switch", "gems"])
        assert result.exit_code == 0
        assert "Switched context to 'gems'." in result.stdout
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "gems*" in result.stdout

    def test_invalid_switch(self, runner):
        result = runner.invoke(context_command_group, ["switch", "invalid"])
        assert result.exit_code == 1
        assert "Context 'invalid' is not defined." in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["switch", "context"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestAdd:
    def test_add(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--name",
                "example",
                "--admin-group-name",
                "Example Admins",
                "--description",
                "Example Deployment",
                "--subscription-name",
                "Data Safe Haven Example",
            ],
        )
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["switch", "example"])
        assert result.exit_code == 0

    def test_add_duplicate(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--admin-group-name",
                "Example Admins",
                "--description",
                "Acme Deployment",
                "--name",
                "acmedeployment",
                "--subscription-name",
                "Data Safe Haven Acme",
            ],
        )
        assert result.exit_code == 1
        assert (
            "A context with name 'acmedeployment' is already defined." in result.stdout
        )

    def test_add_invalid_entra_group_name(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--admin-group-name",
                " Example Admins",
                "--description",
                "Acme Deployment",
                "--name",
                "acmedeployment",
                "--subscription-name",
                "Invalid Subscription Name  ",
            ],
        )
        assert result.exit_code == 2
        assert "Invalid value for '--admin-group-name':" in result.stderr

    def test_add_invalid_subscription_name(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--admin-group-name",
                "Example Admins",
                "--description",
                "Example Deployment",
                "--name",
                "example",
                "--subscription-name",
                "Invalid Subscription Name ^$",
            ],
        )
        assert result.exit_code == 2
        assert "Invalid value for '--subscription-name':" in result.stderr

    def test_add_missing_ags(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--name",
                "example",
            ],
        )
        assert result.exit_code == 2
        assert "Missing option" in result.stderr

    def test_add_bootstrap(self, tmp_contexts, runner):
        (tmp_contexts / "contexts.yaml").unlink()
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "--admin-group-name",
                "Acme Admins",
                "--description",
                "Acme Deployment",
                "--name",
                "acmedeployment",
                "--subscription-name",
                "Data Safe Haven Acme",
            ],
        )
        assert result.exit_code == 0
        assert (tmp_contexts / "contexts.yaml").exists()
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Description: Acme Deployment" in result.stdout
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acmedeployment*" in result.stdout
        assert "gems" not in result.stdout


class TestUpdate:
    def test_update(self, runner):
        result = runner.invoke(
            context_command_group, ["update", "--description", "New Name"]
        )
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Description: New Name" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["update", "--description", "New Name"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestRemove:
    def test_remove(self, runner):
        result = runner.invoke(context_command_group, ["remove", "gems"])
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "gems" not in result.stdout

    def test_remove_invalid(self, runner):
        result = runner.invoke(context_command_group, ["remove", "invalid"])
        assert result.exit_code == 1
        assert "No context with name 'invalid'." in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["remove", "gems"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout
