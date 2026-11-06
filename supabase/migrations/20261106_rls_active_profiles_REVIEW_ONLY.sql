-- LOGBOOK: migração proposta para revisão e teste em staging.
-- NÃO executar em produção antes de validar owner, privilégios e políticas existentes.
-- Requer execução por administrador do banco; função SECURITY DEFINER deve ser
-- proprietária de role confiável com leitura de public.diary_profiles sem RLS recursiva.
begin;

create or replace function public.diary_current_active_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.diary_profiles as p
  where p.id = (select auth.uid())
    and p.active is true
    and p.role = (select auth.jwt() -> 'app_metadata' ->> 'diary_role')
  limit 1
$$;

revoke all on function public.diary_current_active_role() from public;
revoke all on function public.diary_current_active_role() from anon;
grant execute on function public.diary_current_active_role() to authenticated;

-- Evita consulta à própria diary_profiles na expressão da policy.
drop policy if exists "Gestao ve perfis ativos" on public.diary_profiles;
create policy "Gestao ve perfis ativos" on public.diary_profiles
for select to authenticated
using ((select public.diary_current_active_role()) in ('admin','gestor'));

drop policy if exists "Autor ve proprios relatos ou gestor ve todos" on public.diary_entries;
create policy "Autor ve proprios relatos ou gestor ve todos" on public.diary_entries
for select to authenticated
using (
  (select public.diary_current_active_role()) in ('admin','gestor')
  or (
    author_id = (select auth.uid())
    and exists (
      select 1 from public.diary_profiles as p
      where p.id = (select auth.uid()) and p.active is true
    )
  )
);

commit;

-- ATENÇÃO: a policy "Perfil individual" continua permitindo que usuários
-- inativos consultem seu próprio perfil. Avaliar se isso é desejado.
-- TESTES OBRIGATÓRIOS em staging: admin/gestor ativo/inativo, profissional
-- ativo/inativo, JWT com role divergente, anon, ausência de recursão,
-- inserção autorizada e preservação integral do histórico.
