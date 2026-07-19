# Plano futuro: Sincronização do banco entre aparelhos (nuvem)

> Status: **planejado / não implementado.** Hoje o app usa SQLite local (offline).
> Anotado em 2026-06-15 a pedido do usuário.

## Objetivo
Sincronizar o banco local (produtos, preços, lojas, notas) entre vários aparelhos,
sem cabo — fazer login na mesma conta em dois celulares e ver os mesmos dados.

## O que é necessário (3 peças)
1. **Banco na nuvem** — hoje os dados vivem só no SQLite do dispositivo.
2. **Login / conta** — para os aparelhos identificarem que são do mesmo usuário.
3. **Sincronização** — código que envia/recebe mudanças e resolve conflitos.

Os ~42 produtos atuais seriam enviados à nuvem na primeira sincronização (migração inicial).

## Opção recomendada: Firebase (Firestore)
- **Gratuito** para este caso (plano Spark, sem cartão): 1 GB, 50k leituras/dia,
  20k gravações/dia, login ilimitado. Uso pessoal nunca encosta nesses limites.
- **Sync offline automático**: o Firestore mantém cache local e sincroniza sozinho
  quando há internet — o app continua funcionando offline.
- Não mexe na conta Supabase nem nos outros apps do usuário.
- Banco NoSQL (documentos) — diferente do SQL local; exige remodelar a camada de dados.

## Alternativa: Supabase (Postgres)
- SQL como o banco local (familiar), mas:
  - A organização do usuário já está no **limite de 2 projetos free ativos**
    (ccontrol + Saldo-Certo) → exigiria pausar um app ou pagar o Pro (~US$ 25/mês).
  - O **sync offline não é nativo** — teria que ser implementado manualmente.

## Esforço estimado (Firebase)
Refatoração média/grande, recomendada em etapas testáveis:
1. Adicionar Firebase ao projeto (`firebase_core`, `cloud_firestore`, `firebase_auth`).
2. Tela de **login** (e-mail/senha ou Google).
3. **Camada de repositório** que espelha os DAOs atuais, mas lendo/gravando no Firestore
   (mantendo a estrutura: produtos, registros, lojas, locais, notas_importadas).
4. **Migração inicial**: enviar os dados do SQLite local para o Firestore na 1ª sync.
5. Regras de segurança do Firestore (cada usuário só acessa os próprios dados).
6. (Opcional) Estratégia de conflito quando o mesmo registro é editado em 2 aparelhos.

## Decisão pendente
Confirmar com o usuário se seguimos com **Firebase** quando ele quiser priorizar isso.
