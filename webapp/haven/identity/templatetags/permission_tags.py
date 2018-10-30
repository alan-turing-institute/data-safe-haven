from django import template


register = template.Library()


@register.simple_tag(takes_context=True)
def can_create_users(context):
    return context['user'].can_create_users


@register.simple_tag(takes_context=True)
def can_create_projects(context):
    return context['user'].can_create_projects


@register.simple_tag(takes_context=True)
def can_add_user_to_project(context, project):
    return context['user'].can_add_user_to_project(project)
