import http from 'k6/http'

import {sleep } from 'k6';

export const options = {
    iterations: 10,
    }

export default function (){
    http.get('http://10.14.1.185')

    sleep(1);
}