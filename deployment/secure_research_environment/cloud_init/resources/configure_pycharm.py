"""Generate a PyCharm XML configuration file"""
import io
import os
import sys
import xml.etree.ElementTree as ElementTree


def generate_xml_output(target):
    """Generate a PyCharm XML configuration file"""
    # Construct by find-and-replace on a template XML file
    jdk_output = ["<application>", '<component name="ProjectJdkTable">']
    with open("/opt/configuration/jdk-template.xml", "r") as f_jdk:
        jdk_template_lines = [line.strip() for line in f_jdk.readlines()]
    for python_version in sorted(os.listdir("/opt/pyenv/versions")):
        python_short_version = ".".join(python_version.split(".")[0:2])
        python_environment = f"py{python_short_version.replace('.', '')}"
        jdk_output += [
            line.replace(r"{{python_version}}", python_version)
            .replace(r"{{python_short_version}}", python_short_version)
            .replace(r"{{python_environment}}", python_environment)
            for line in jdk_template_lines
            if line
        ]
    jdk_output += ["</component>", "</application>"]

    # Write out via ElementTree to validate our XML
    print(f"Writing XML output to {target}")
    tree = ElementTree.parse(io.StringIO("\n".join(jdk_output)))
    tree.write(target)


if __name__ == "__main__":
    generate_xml_output(sys.argv[1])
