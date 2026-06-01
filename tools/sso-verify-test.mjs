import crypto from 'node:crypto';
// Mirror of warden-worker verify_id_token: RS256 over header.payload, JWK by kid, iss/aud/exp/nonce.
const b64u = b => Buffer.from(b).toString('base64url');
const jwkFromPub = (pub, kid) => ({ ...pub.export({format:'jwk'}), kid, use:'sig', alg:'RS256' });
function signJwt(payload, priv, kid){
  const h = b64u(JSON.stringify({alg:'RS256',typ:'JWT',kid}));
  const p = b64u(JSON.stringify(payload));
  const s = crypto.createSign('RSA-SHA256').update(`${h}.${p}`).sign(priv).toString('base64url');
  return `${h}.${p}.${s}`;
}
function verify(idToken, jwks, {issuer, clientId, nonce}){
  const [h,p,s] = idToken.split('.');
  const hdr = JSON.parse(Buffer.from(h,'base64url'));
  const payload = JSON.parse(Buffer.from(p,'base64url'));
  const jwk = jwks.keys.find(k => k.kid===hdr.kid);
  if(!jwk) throw new Error('no matching JWKS key');
  const key = crypto.createPublicKey({key:jwk, format:'jwk'});
  const ok = crypto.createVerify('RSA-SHA256').update(`${h}.${p}`).verify(key, Buffer.from(s,'base64url'));
  if(!ok) throw new Error('signature invalid');
  if(payload.iss!==issuer) throw new Error('iss mismatch');
  const aud = Array.isArray(payload.aud)?payload.aud:[payload.aud];
  if(!aud.includes(clientId)) throw new Error('aud mismatch');
  if(payload.exp && payload.exp < Math.floor(Date.now()/1000)) throw new Error('expired');
  if(nonce && payload.nonce!==nonce) throw new Error('nonce mismatch');
  return payload;
}
// ---- correctness cases against a controlled IdP ----
const {publicKey,privateKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
const kid='test-key-1', jwks={keys:[jwkFromPub(publicKey,kid)]};
const base={iss:'https://idp.example.com',aud:'client-123',sub:'user-abc',email:'test@example.com',exp:Math.floor(Date.now()/1000)+300,nonce:'NONCE1'};
const opts={issuer:base.iss,clientId:base.aud,nonce:base.nonce};
let pass=0,fail=0; const t=(n,fn,shouldThrow)=>{try{fn();if(shouldThrow){console.log('✗',n,'(expected reject)');fail++}else{console.log('✓',n);pass++}}catch(e){if(shouldThrow){console.log('✓',n,'→ rejected:',e.message);pass++}else{console.log('✗',n,'→',e.message);fail++}}};
t('valid token accepted',()=>verify(signJwt(base,privateKey,kid),jwks,opts),false);
t('tampered payload rejected',()=>{const tok=signJwt(base,privateKey,kid).split('.');tok[1]=b64u(JSON.stringify({...base,email:'attacker@evil.com'}));verify(tok.join('.'),jwks,opts)},true);
t('wrong audience rejected',()=>verify(signJwt({...base,aud:'other-client'},privateKey,kid),jwks,opts),true);
t('expired token rejected',()=>verify(signJwt({...base,exp:Math.floor(Date.now()/1000)-10},privateKey,kid),jwks,opts),true);
t('bad nonce rejected',()=>verify(signJwt({...base,nonce:'WRONG'},privateKey,kid),jwks,opts),true);
t('wrong issuer rejected',()=>verify(signJwt({...base,iss:'https://evil.com'},privateKey,kid),jwks,opts),true);
// ---- compatibility: Google's REAL discovery + JWKS shape ----
const disc=await (await fetch('https://accounts.google.com/.well-known/openid-configuration')).json();
const gjwks=await (await fetch(disc.jwks_uri)).json();
const k0=gjwks.keys[0];
const shapeOK = !!disc.issuer && !!disc.jwks_uri && Array.isArray(gjwks.keys) && k0.kty==='RSA' && k0.n && k0.e && k0.kid;
console.log(shapeOK?'✓':'✗','Google live discovery+JWKS shape matches verify_id_token expectations',`(issuer=${disc.issuer}, keys=${gjwks.keys.length})`);
shapeOK?pass++:fail++;
console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
