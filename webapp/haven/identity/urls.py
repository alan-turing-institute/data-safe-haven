from django.urls import path

from . import views


app_name = 'identity'

urlpatterns = [
    path('new', views.UserCreate.as_view(), name='add_user'),
]
