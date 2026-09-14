/*
-- CHA_ETL.sql
-- ETL: OLTP (schema oper_cha, ver CHA_DDL) -> DW (schema dw_cha)
-- Ordem: dimensões primeiro (por causa das FKs), fato(s) por último
*/

SET search_path = dw_cha;

-- 1) Data_DIMENSION
-- Grão: 1 linha por data distinta em que houve uma TransVenda
INSERT INTO Data_DIMENSION (dt_SK, dt_data_completa, dt_dia_semana, dt_dia_mes, dt_mes, dt_ano, dt_trimestre)
SELECT DISTINCT
    CAST(TO_CHAR(tv.TransVendaData, 'YYYYMMDD') AS INT)  AS dt_SK,
    tv.TransVendaData                                     AS dt_data_completa,
    EXTRACT(DOW  FROM tv.TransVendaData)::INT             AS dt_dia_semana,
    EXTRACT(DAY  FROM tv.TransVendaData)::INT             AS dt_dia_mes,
    EXTRACT(MONTH FROM tv.TransVendaData)::INT            AS dt_mes,
    EXTRACT(YEAR FROM tv.TransVendaData)::INT             AS dt_ano,
    EXTRACT(QUARTER FROM tv.TransVendaData)::INT          AS dt_trimestre
FROM oper_cha.TransVenda tv
ON CONFLICT (dt_SK) DO NOTHING;

-- 2) Corretor_DIMENSION (SCD Tipo 2 — carga inicial: tudo entra como versão atual)
INSERT INTO Corretor_DIMENSION (cor_CPF, cor_registro, cor_nome, cor_sobrenome, cor_dt_inicio, cor_dt_fim, cor_is_atual)
SELECT
    co.FuncCPF,
    co.CorretorRegistro,
    f.FuncPrimNome,
    f.FuncUltimoNome,
    CURRENT_TIMESTAMP AS cor_dt_inicio,
    NULL               AS cor_dt_fim,
    TRUE               AS cor_is_atual
FROM oper_cha.Corretor co
JOIN oper_cha.Funcionario f ON f.FuncCPF = co.FuncCPF;

-- 3) Cliente_DIMENSION (SCD Tipo 2 — carga inicial)
INSERT INTO Cliente_DIMENSION (cl_CPF, cl_nome, cl_sobrenome, cl_dt_inicio, cl_dt_fim, cl_is_atual)
SELECT
    c.ClienteCPF,
    c.ClientePrimNome,
    c.CliUltimoNome,
    CURRENT_TIMESTAMP AS cl_dt_inicio,
    NULL               AS cl_dt_fim,
    TRUE               AS cl_is_atual
FROM oper_cha.Cliente c;

-- 4) Imovel_DIMENSION (SCD Tipo 2 — carga inicial)
-- Endereço vem de Endereco -> CEP -> UF
-- Métricas de anúncio (im_num_anuncios, im_gasto_em_anuncios) são agregadas de Anuncio
INSERT INTO Imovel_DIMENSION (im_ID, im_logradouro, im_bairro, im_cidade, im_estado,
                               im_num_anuncios, im_gasto_em_anuncios,
                               im_dt_inicio, im_dt_fim, im_is_atual)
SELECT
    i.ImovelID,
    cep.NmLogradouro,
    e.EndBairro,
    cep.CEPMunicipio,
    uf.UFEstadoNome,
    COALESCE(anu.num_anuncios, 0)   AS im_num_anuncios,
    COALESCE(anu.gasto_total, 0)    AS im_gasto_em_anuncios,
    CURRENT_TIMESTAMP AS im_dt_inicio,
    NULL               AS im_dt_fim,
    TRUE               AS im_is_atual
FROM oper_cha.Imovel i
JOIN oper_cha.Endereco e ON e.EndID = i.EndID
JOIN oper_cha.CEP cep    ON cep.CEP = e.CEP
JOIN oper_cha.UF uf      ON uf.UF = cep.UF
LEFT JOIN (
    SELECT ImovelID,
           COUNT(*)              AS num_anuncios,
           SUM(AnuncioPreco)     AS gasto_total
    FROM oper_cha.Anuncio
    GROUP BY ImovelID
) anu ON anu.ImovelID = i.ImovelID;

-- 5) Trans_Venda_FACT
-- Grão: 1 linha por transação de venda
INSERT INTO Trans_Venda_FACT (tv_ID, tv_valor, tv_comissao, cor_SK, im_SK, dt_SK)
SELECT
    tv.TransVendaID,
    tv.TransVendaValor,
    tv.TransComissao,
    cor.cor_SK,
    im.im_SK,
    dt.dt_SK
FROM oper_cha.TransVenda tv
JOIN Corretor_DIMENSION cor
    ON cor.cor_CPF = tv.FuncCPF
   AND cor.cor_is_atual = TRUE
JOIN oper_cha.ImovelTransacao it
    ON it.TransVendaID = tv.TransVendaID
JOIN Imovel_DIMENSION im
    ON im.im_ID = it.ImovelID
   AND im.im_is_atual = TRUE
JOIN Data_DIMENSION dt
    ON dt.dt_data_completa = tv.TransVendaData;

-- 6) Vendedor_PONTE
-- Origem: ClienteVende (N:N) -> liga cada transação aos seus vendedores
INSERT INTO Vendedor_PONTE (tv_SK, cl_SK)
SELECT
    fv.tv_SK,
    cl.cl_SK
FROM oper_cha.ClienteVende cv
JOIN Trans_Venda_FACT fv
    ON fv.tv_ID = cv.TransVendaID
JOIN Cliente_DIMENSION cl
    ON cl.cl_CPF = cv.ClienteCPF
   AND cl.cl_is_atual = TRUE;

-- 7) Comprador_PONTE
-- Origem: ClienteCompra (N:N) -> liga cada transação aos seus compradores
INSERT INTO Comprador_PONTE (tv_SK, cl_SK)
SELECT
    fv.tv_SK,
    cl.cl_SK
FROM oper_cha.ClienteCompra cc
JOIN Trans_Venda_FACT fv
    ON fv.tv_ID = cc.TransVendaID
JOIN Cliente_DIMENSION cl
    ON cl.cl_CPF = cc.ClienteCPF
   AND cl.cl_is_atual = TRUE;

-- 8) Receita_Agregada_FACT
-- Grão: 1 linha por (imóvel, dia)
INSERT INTO Receita_Agregada_FACT (ra_comissao_total, im_SK, dt_SK)
SELECT
    SUM(tv.TransComissao) AS ra_comissao_total,
    im.im_SK,
    dt.dt_SK
FROM oper_cha.TransVenda tv
JOIN oper_cha.ImovelTransacao it ON it.TransVendaID = tv.TransVendaID
JOIN Imovel_DIMENSION im ON im.im_ID = it.ImovelID AND im.im_is_atual = TRUE
JOIN Data_DIMENSION dt ON dt.dt_data_completa = tv.TransVendaData
GROUP BY im.im_SK, dt.dt_SK;