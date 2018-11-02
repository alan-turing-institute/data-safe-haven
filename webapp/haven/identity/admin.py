from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class IdentityUserAdmin(UserAdmin):
    list_display = 'username', 'email', 'role', 'is_staff'

    fieldsets = UserAdmin.fieldsets + (
        ('Extra fields', {
            'fields': ['role']
        }),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('Extra fields', {
            'fields': ['role']
        }),
    )
