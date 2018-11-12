from braces.forms import UserKwargModelFormMixin
from django.contrib.auth.mixins import UserPassesTestMixin


class UserRoleRequiredMixin(UserPassesTestMixin):
    """
    View mixin to ensure only certain user roles are able to access the view
    """
    user_roles = []

    def test_func(self):
        return (
            self.request.user.is_superuser or
            self.request.user.user_role in self.user_roles
        )


class SaveCreatorMixin(UserKwargModelFormMixin):
    """
    Form mixin to record the user that created an object

    Must be used on a `ModelForm` on which the model class has a `created_by`
    foreign key to `identity.User`
    """
    def save(self, **kwargs):
        obj = super().save(commit=False)
        obj.created_by = self.user
        obj.save()
        self.save_m2m()
        return obj
