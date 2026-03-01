{% for component_id, component in components.items() %}
{% if component.component_type == "core" %}

; --- Core ---
.setcpu "{{ component.cpu }}"
CPU_CLOCK = {{ component.clock_hz }}
{% elif component.component_type == "via_w65c22" and component.address is defined %}

; --- {{ component_id }} ---
{{ component_id }}_BASE = {{ component.address }}
{% for name, offset in component.registers %}
{{ component_id }}_{{ name }} = {{ component_id }}_BASE + {{ offset | hex }}
{% endfor %}
{% endif %}
{% endfor %}
