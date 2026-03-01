; W65C22 VIA register addresses: {{ component_id }} (base {{ address | hex }})

{{ symbol_prefix }}_BASE = {{ address | hex }}
{% for name, offset in registers %}
{{ symbol_prefix }}_{{ name }} = {{ symbol_prefix }}_BASE + {{ offset | hex }}
{% endfor %}
