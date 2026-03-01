{% for component_id, component in components.items() %}
{% if component.component_type == "core" %}

; --- Core ---
.setcpu "{{ component.cpu }}"
CPU_CLOCK = {{ component.clock_hz }}
{% endif %}
{% endfor %}
