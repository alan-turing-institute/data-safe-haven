from django import template


register = template.Library()


@register.simple_tag(takes_context=True)
def can_create_users(context):
    return context['user'].user_role.can_create_users


@register.simple_tag(takes_context=True)
def can_create_projects(context):
    return context['user'].user_role.can_create_projects


@register.simple_tag(takes_context=True)
def can_add_participant(context, project):
    return context['user'].project_role(project).can_add_participant


@register.simple_tag(takes_context=True)
def can_list_participants(context, project):
    return context['user'].project_role(project).can_list_participants
