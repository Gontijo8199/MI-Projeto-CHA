/*
-- CHA_F2_ETL_carga_incremental.sql  (Fase II) - idempotente
-- Ordem de execução numa carga mensal:
--   1. python etl_python/01_transformar_fipezap.py data_lake/bronze/fipezap/<novo xlsx> data_lake/silver/fipezap_preco_m2.csv
--   2. TRUNCATE stg_fipezap; \copy stg_fipezap FROM '...silver/fipezap_preco_m2.csv' WITH CSV HEADER
--   3. ETL incremental da Fase 1 (CHA_ETL_carga_incremental_pulverizado.sql)
--   4. ESTE script
*/
SET search_path = dw_cha_pulverizado;

-- 1) Mercado_FIPEZAP_DIMENSION: insere meses novos e aplica revisões da Fipe (Tipo 1)
INSERT INTO Mercado_FIPEZAP_DIMENSION
  (mk_cidade, mk_cidade_norm, mk_mes, mk_dormitorios, mk_preco_m2, mk_var_mensal, mk_var_12m)
SELECT cidade, cidade_norm, mes, dormitorios, preco_m2, var_mensal, var_12m
FROM stg_fipezap
ON CONFLICT (mk_cidade_norm, mk_mes, mk_dormitorios) DO UPDATE
SET mk_preco_m2   = EXCLUDED.mk_preco_m2,
    mk_var_mensal = EXCLUDED.mk_var_mensal,
    mk_var_12m    = EXCLUDED.mk_var_12m,
    mk_dt_carga   = CURRENT_TIMESTAMP
WHERE (Mercado_FIPEZAP_DIMENSION.mk_preco_m2, Mercado_FIPEZAP_DIMENSION.mk_var_12m)
      IS DISTINCT FROM (EXCLUDED.mk_preco_m2, EXCLUDED.mk_var_12m);

-- 2) Imovel_DIMENSION (SCD2) - novos atributos
-- 2.0 versões criadas pelo ETL da Fase 1 nascem sem os atributos novos: preenche (não é mudança real)
UPDATE Imovel_DIMENSION im
SET im_tipo = i.ImovelTipo, im_qtd_quartos = i.ImovelQtdQuartos, im_m2 = i.ImovelM2
FROM oper_cha.Imovel i
WHERE im.im_ID = i.ImovelID AND im.im_is_atual = TRUE AND im.im_tipo IS NULL;

-- 2.1 fecha a versão atual se tipo / quartos / m² mudaram no operacional
UPDATE Imovel_DIMENSION im
SET im_dt_fim = CURRENT_TIMESTAMP, im_is_atual = FALSE
FROM oper_cha.Imovel i
WHERE im.im_ID = i.ImovelID AND im.im_is_atual = TRUE
  AND (im.im_tipo, im.im_qtd_quartos, im.im_m2)
      IS DISTINCT FROM (i.ImovelTipo, i.ImovelQtdQuartos, i.ImovelM2);

-- 2.2 insere a nova versão (copia o restante da versão recém-fechada)
INSERT INTO Imovel_DIMENSION (im_ID, im_logradouro, im_bairro, im_cidade, im_estado,
                              im_num_anuncios, im_gasto_em_anuncios,
                              im_tipo, im_qtd_quartos, im_m2,
                              im_dt_inicio, im_dt_fim, im_is_atual)
SELECT old.im_ID, old.im_logradouro, old.im_bairro, old.im_cidade, old.im_estado,
       old.im_num_anuncios, old.im_gasto_em_anuncios,
       i.ImovelTipo, i.ImovelQtdQuartos, i.ImovelM2,
       CURRENT_TIMESTAMP, NULL, TRUE
FROM Imovel_DIMENSION old
JOIN oper_cha.Imovel i ON i.ImovelID = old.im_ID
WHERE old.im_is_atual = FALSE
  AND old.im_dt_fim = (SELECT MAX(x.im_dt_fim) FROM Imovel_DIMENSION x WHERE x.im_ID = old.im_ID)
  AND NOT EXISTS (SELECT 1 FROM Imovel_DIMENSION cur WHERE cur.im_ID = old.im_ID AND cur.im_is_atual = TRUE);

-- 3) Trans_Venda_FACT: R$/m² e ligação ao benchmark só para linhas ainda não resolvidas
UPDATE Trans_Venda_FACT f
SET tv_valor_m2 = f.tv_valor / NULLIF(im.im_m2, 0)
FROM Imovel_DIMENSION im
WHERE im.im_SK = f.im_SK AND f.tv_valor_m2 IS NULL;

UPDATE Trans_Venda_FACT f
SET mk_SK = (
  SELECT mk.mk_SK
  FROM Mercado_FIPEZAP_DIMENSION mk
  WHERE mk.mk_cidade_norm = fn_norm_cidade(im.im_cidade)
    AND mk.mk_mes         = DATE_TRUNC('month', dt.dt_data_completa)::DATE
    AND mk.mk_dormitorios IN (CASE WHEN im.im_qtd_quartos >= 1
                                   THEN LEAST(im.im_qtd_quartos, 4) || 'D' ELSE 'Total' END, 'Total')
  ORDER BY (mk.mk_dormitorios = 'Total')   -- prefere a faixa exata; cai para 'Total' (ex.: Vitória só tem Total)
  LIMIT 1
)
FROM Imovel_DIMENSION im, Data_DIMENSION dt
WHERE im.im_SK = f.im_SK
  AND dt.dt_SK = f.dt_SK
  AND f.mk_SK IS NULL
  AND im.im_tipo = 'Apartamento';
