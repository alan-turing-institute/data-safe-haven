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


class TestUpload:
    def test_upload(self, runner, config_file, mock_upload_blob):
        result = runner.invoke(
            config_command_group,
            ["upload", str(config_file)],
        )
        assert result.exit_code == 0

    def test_upload_no_file(self, runner, mock_upload_blob):
        result = runner.invoke(
            config_command_group,
            ["upload"],
        )
        assert result.exit_code == 2


class TestShow:
    def test_show(self, runner, config_yaml, mock_download_blob):
        result = runner.invoke(
            config_command_group,
            ["show"]
        )
        assert result.exit_code == 0
        assert config_yaml in result.stdout
