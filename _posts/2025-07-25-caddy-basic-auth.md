---
title:  "Caddy, skip basic auth from internal network"
categories: homelab
---

Skip basic auth if the request is coming from a specific network


```
(internal_network) {
        @internal {
                remote_ip 10.0.0.0/23 ::1
        }
        @not-local {
                not remote_ip 10.0.0.0/23 ::1
        }
}

my.host.com:443 {
        import internal_network
        reverse_proxy {
                to backend1:1234 backend2:12334
                lb_policy weighted_round_robin 1 6
        }
        basic_auth @not-local {
                $user $password_hash
        }
}
```
