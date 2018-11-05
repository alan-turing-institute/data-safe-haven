"""haven URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/2.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.contrib import admin
from django.contrib.auth import views as auth_views
from django.urls import include, path
from django.views.generic import TemplateView


urlpatterns = [
    path('admin/', admin.site.urls),

    path('users/', include('identity.urls', namespace='identity')),

    path('projects/', include('projects.urls', namespace='projects')),

    path(
        'accounts/login/',
        auth_views.LoginView.as_view(template_name='identity/login.html'),
        name='login'
    ),

    path(
        'accounts/logout/',
        auth_views.LogoutView.as_view(),
        name='logout'
    ),


    path('', TemplateView.as_view(template_name='home.html'), name='home')
]

if settings.DEBUG:
    import debug_toolbar
    urlpatterns = [
        path('__debug__/', include(debug_toolbar.urls)),
    ] + urlpatterns
