/*
-- CHA_F2_ETL_carga_inicial.sql  (Fase II)
-- Pré-requisitos: CHA_F2_DDL_fipezap.sql executado e stg_fipezap carregada:
--   TRUNCATE dw_cha_pulverizado.stg_fipezap;
--   \copy dw_cha_pulverizado.stg_fipezap FROM 'data_lake/silver/fipezap_preco_m2.csv' WITH CSV HEADER
*/
SET search_path = dw_cha_pulverizado;

-- 1) Mercado_FIPEZAP_DIMENSION
INSERT INTO Mercado_FIPEZAP_DIMENSION
  (mk_cidade, mk_cidade_norm, mk_mes, mk_dormitorios, mk_preco_m2, mk_var_mensal, mk_var_12m)
SELECT cidade, cidade_norm, mes, dormitorios, preco_m2, var_mensal, var_12m
FROM stg_fipezap
ON CONFLICT (mk_cidade_norm, mk_mes, mk_dormitorios) DO NOTHING;

-- 2) Imovel_DIMENSION: preenche os novos atributos nas versões atuais (carga inicial das colunas novas)
UPDATE Imovel_DIMENSION im
SET im_tipo = i.ImovelTipo, im_qtd_quartos = i.ImovelQtdQuartos, im_m2 = i.ImovelM2
FROM oper_cha.Imovel i
WHERE im.im_ID = i.ImovelID AND im.im_is_atual = TRUE AND im.im_tipo IS NULL;

-- 3) Trans_Venda_FACT: R$/m² da venda
UPDATE Trans_Venda_FACT f
SET tv_valor_m2 = f.tv_valor / NULLIF(im.im_m2, 0)
FROM Imovel_DIMENSION im
WHERE im.im_SK = f.im_SK AND f.tv_valor_m2 IS NULL;

-- 4) Trans_Venda_FACT: liga ao benchmark (cidade + mês da venda + faixa de dormitórios)
--    Só apartamentos: o FipeZAP mede apartamentos prontos.
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
