
.setcpu "{{ config.core.cpu }}"

; Component includes.
{% for inc_path in component_includes %}
.include "{{ inc_path }}"
{% endfor %}
