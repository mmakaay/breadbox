; W65C22 VIA register addresses: {{ component_id }} (base {{ address | hex }})

{{ constant("BASE") }} = {{ address | hex }}
{% for name, offset in registers %}
{{ constant(name) }} = {{ constant("BASE") }} + {{ offset | hex }}
{% endfor %}
