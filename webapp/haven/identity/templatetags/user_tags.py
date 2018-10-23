from django import template

from ..roles import UserRole


register = template.Library()


@register.filter
def show_create_user_page(user):
    return UserRole.can_access_user_creation_page(user)
