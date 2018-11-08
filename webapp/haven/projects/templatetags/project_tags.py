from django import template
from django.template.defaultfilters import stringfilter

from ..roles import ProjectRole


register = template.Library()


@register.filter
@stringfilter
def project_role_display(role):
    return dict(ProjectRole.choices()).get(role, '')
