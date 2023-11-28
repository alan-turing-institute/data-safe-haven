from data_safe_haven.commands.config import config_command_group


class TestTemplate:
    def test_template(self, runner):
        result = runner.invoke(config_command_group, ["template"])
        assert result.exit_code == 0
        assert "subscription_id: Azure subscription ID" in result.stdout
        assert "sres: {}" in result.stdout

    def test_template_file(self, runner, tmp_path):
        template_file = (tmp_path / "template.yaml").absolute()
        result = runner.invoke(config_command_group, ["template", "--file", str(template_file)])
        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert "subscription_id: Azure subscription ID" in template_text
        assert "sres: {}" in template_text
