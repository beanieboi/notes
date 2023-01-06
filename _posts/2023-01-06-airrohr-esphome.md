---
title:  "Running Luftdaten-Sensor (aka Airrohr) with ESPHome instead of stock firmware"
categories: home-automation
---

Below is my configuration for the ESP8266 with SDS011 and BME280 sensors. The main reason the run it with ESPHome instead of the stock firmware is direct integration into Home Assistant and native MQTT support.
I still push my data to opensensemap.org but it's now handled by Home Assistant instead. I used the following instructions to set up the opensensemap integration: [https://hmmbob.tweakblogs.net/blog/18950/push-data-to-luftdaten-and-opensensemap-with-home-assistant](https://hmmbob.tweakblogs.net/blog/18950/push-data-to-luftdaten-and-opensensemap-with-home-assistant)

```yaml
esphome:
  name: airrohr
  platform: ESP8266
  board: nodemcuv2

# Enable logging
logger:
 level: WARN

# Enable Home Assistant API
api:

ota:

button:
  - platform: restart
    name: "Airrohr Restart"

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  fast_connect: true

mqtt:
  broker: 192.168.1.5
  port: 1883
  username: beanieboi
  password: !secret mqtt_password
  topic_prefix: home/balcony/airrohr
  discovery: false

uart:
  rx_pin: D1
  tx_pin: D2
  baud_rate: 9600

i2c:
  sda: D3
  scl: D4

sensor:
  - platform: sds011
    pm_2_5:
      id: balcony_pm_2_5um
      name: "Balcony PM <2.5µm"
      state_topic: home/balcony/airrohr/pm_2_5
    pm_10_0:
      id: balcony_pm_10_0um
      name: "Balcony PM <10.0µm"
      state_topic: home/balcony/airrohr/pm_10_0
    update_interval: 2min

  - platform: bme280
    temperature:
      id: balcony_temperature
      name: "Balcony Temperature"
      oversampling: 16x
      state_topic: home/balcony/airrohr/temperature
    pressure:
      id: balcony_pressure
      name: "Balcony Pressure"
      state_topic: home/balcony/airrohr/pressure
    humidity:
      id: balcony_humidity
      name: "Balcony Humidity"
      state_topic: home/balcony/airrohr/humidity
    address: 0x76
    update_interval: 2min

  - platform: wifi_signal
    name: "Airrohr WiFi Signal"
    id: airrohr_wifi_signal
    update_interval: 2min

  - platform: template
    name: "Airrohr WiFi Quality"
    update_interval: 2min
    unit_of_measurement: "%"
    icon: "mdi:wifi"
    lambda: |-
      if (id(airrohr_wifi_signal).state <= -100) {
        return 0;
      } else if (id(airrohr_wifi_signal).state >= -50) {
        return 100;
      } else {
        return 2 * (id(airrohr_wifi_signal).state + 100);
      }
```
