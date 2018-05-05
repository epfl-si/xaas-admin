# -*- coding: utf-8 -*-
# Generated by Django 1.11.13 on 2018-05-05 10:25
from __future__ import unicode_literals

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='FacultyAdmin',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=50)),
            ],
        ),
        migrations.CreateModel(
            name='ItsAdmin',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('active_directory_group', models.CharField(max_length=50)),
            ],
        ),
        migrations.CreateModel(
            name='MyVMQuota',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('year', models.IntegerField()),
                ('cpu_number', models.IntegerField(null=True)),
                ('ram_mb', models.IntegerField(null=True)),
                ('hdd_gb', models.IntegerField(null=True)),
                ('cpu_nb_used', models.IntegerField(null=True)),
                ('ram_mb_used', models.IntegerField(null=True)),
                ('hdd_gb_used', models.IntegerField(null=True)),
                ('used_last_update', models.DateTimeField(null=True)),
                ('cpu_nb_reserved', models.IntegerField(null=True)),
                ('ram_mb_reserved', models.IntegerField(null=True)),
                ('hdd_gb_reserved', models.IntegerField(null=True)),
                ('faculty', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='quotas.FacultyAdmin')),
            ],
        ),
        migrations.AddField(
            model_name='facultyadmin',
            name='its_admin',
            field=models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='quotas.ItsAdmin'),
        ),
    ]
