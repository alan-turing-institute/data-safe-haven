from django.contrib.auth.mixins import UserPassesTestMixin


class UserRoleRequiredMixin(UserPassesTestMixin):
    user_roles = []

    def test_func(self):
        return (
            self.request.user.is_superuser or
            self.request.user.role in self.user_roles
        )
