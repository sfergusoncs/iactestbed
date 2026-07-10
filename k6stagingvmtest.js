import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    login_bursts: {
      executor: 'per-vu-iterations',
      vus: 5,
      iterations: 10,
      maxDuration: '5m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<3000'],
  },
};

const LOGIN_URL = 'https://skynet-api-staging.chalksolutions.com/api/login/';
const CREDENTIALS = JSON.stringify({
  username: 'sferguson',
  password: 'iwbi86iSG!@#$%^',
});

export default function () {
   // Fresh cookie jar every iteration — no affinity cookie carried forward
  const jar = new http.CookieJar();
    
  const res = http.post(LOGIN_URL, CREDENTIALS, {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Origin': 'https://sandman-staging.chalksolutions.com',
      'Referer': 'https://sandman-staging.chalksolutions.com/',
    },
    timeout: '10s',
  });

  check(res, {
    'status 200': (r) => r.status === 200,
    'has token': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.token !== undefined || body.access !== undefined || body.key !== undefined;
      } catch {
        return false;
      }
    },
  });

  sleep(25);
}