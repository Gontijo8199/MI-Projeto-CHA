#!/usr/bin/env bash
# Pipeline completa Fase 1 + Fase 2 (DW Pulverizado + Data Lake bronze/silver/gold).
# Uso (na raiz do repositório): ./run_pipeline.sh <banco>   ex.: createdb cha_db && ./run_pipeline.sh cha_db
set -euo pipefail
DB=${1:?uso: ./run_pipeline.sh <banco>}
PY=${PYTHON:-python3}
XLSX=$(ls data_lake/bronze/fipezap/*.xlsx | sort | tail -1)   # planilha mais recente da Fipe
psql() { PGOPTIONS='-c client_min_messages=warning' command psql -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }

# 1) OLTP + DW Fase 1 (os DDLs fazem DROP SCHEMA CASCADE: precisam vir antes da Fase 2)
psql -f db_operacional/CHA_DDL_create_oper_db.sql -f db_operacional/CHA_DML_populate_oper_db.sql
psql -f db_pulverizada/CHA_DDL_create_dw_db_pulverizado.sql -f db_pulverizada/CHA_ETL_carga_inicial_pulverizado.sql

# 2) BRONZE -> SILVER (fonte externa)
"$PY" etl_python/01_transformar_fipezap.py "$XLSX" data_lake/silver/fipezap_preco_m2.csv

# 3) SILVER -> DW (Fase 2)
psql -f db_fase2/CHA_F2_DDL_fipezap.sql \
     -c "TRUNCATE dw_cha_pulverizado.stg_fipezap" \
     -c "\copy dw_cha_pulverizado.stg_fipezap FROM 'data_lake/silver/fipezap_preco_m2.csv' WITH CSV HEADER" \
     -f db_fase2/CHA_F2_ETL_carga_inicial.sql

# 4) BRONZE: snapshot do operacional (linhagem da fonte interna)
mkdir -p data_lake/bronze/oper_cha data_lake/gold
for t in $(psql -At -c "SELECT tablename FROM pg_tables WHERE schemaname='oper_cha' ORDER BY 1"); do
  psql -c "\copy oper_cha.$t TO 'data_lake/bronze/oper_cha/$t.csv' WITH CSV HEADER"
done

# 5) GOLD: estrela + view + mercado das cidades em que atuamos (consumo do dashboard)
for t in corretor_dimension cliente_dimension imovel_dimension data_dimension trans_venda_fact \
         receita_agregada_fact vw_venda_vs_mercado; do
  psql -c "\copy (SELECT * FROM dw_cha_pulverizado.$t) TO 'data_lake/gold/$t.csv' WITH CSV HEADER"
done
psql -c "\copy (SELECT * FROM dw_cha_pulverizado.mercado_fipezap_dimension WHERE mk_cidade_norm IN (SELECT dw_cha_pulverizado.fn_norm_cidade(im_cidade) FROM dw_cha_pulverizado.imovel_dimension) ORDER BY mk_cidade_norm, mk_mes, mk_dormitorios) TO 'data_lake/gold/mercado_fipezap_dimension.csv' WITH CSV HEADER"

echo "OK: $(psql -At -c "SELECT format('%s/%s vendas com benchmark', COUNT(agio_vs_mercado), COUNT(*)) FROM dw_cha_pulverizado.vw_venda_vs_mercado")"
