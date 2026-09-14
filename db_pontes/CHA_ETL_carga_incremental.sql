/*
-- CHA_ETL_incremental.sql
-- ETL INCREMENTAL: OLTP (schema oper_cha) -> DW (schema dw_cha)
-- Pode ser rodado repetidamente (idempotente) a cada nova carga.
-- Lógica: dimensões SCD2 primeiro (fecha versão antiga + insere nova),
-- depois fato, depois pontes, por último o fato agregado.
*/

SET search_path = dw_cha;

-- 1) Data_DIMENSION — só insere datas novas (chave natural = dt_SK gerado da data)
INSERT INTO Data_DIMENSION (dt_SK, dt_data_completa, dt_dia_semana, dt_dia_mes, dt_mes, dt_ano, dt_trimestre)
SELECT DISTINCT
    CAST(TO_CHAR(tv.TransVendaData, 'YYYYMMDD') AS INT),
    tv.TransVendaData,
    EXTRACT(DOW  FROM tv.TransVendaData)::INT,
    EXTRACT(DAY  FROM tv.TransVendaData)::INT,
    EXTRACT(MONTH FROM tv.TransVendaData)::INT,
    EXTRACT(YEAR FROM tv.TransVendaData)::INT,
    EXTRACT(QUARTER FROM tv.TransVendaData)::INT
FROM oper_cha.TransVenda tv
WHERE NOT EXISTS (
    SELECT 1 FROM Data_DIMENSION d
    WHERE d.dt_SK = CAST(TO_CHAR(tv.TransVendaData, 'YYYYMMDD') AS INT)
);

-- 2) Corretor_DIMENSION (SCD Tipo 2)
-- 2.1 Fecha a versão atual de quem mudou algum atributo rastreado
-- 2.2 Insere nova versão para: corretores novos + corretores que mudaram
UPDATE Corretor_DIMENSION cd
SET cor_dt_fim = CURRENT_TIMESTAMP,
    cor_is_atual = FALSE
FROM (
    SELECT co.FuncCPF, co.CorretorRegistro, f.FuncPrimNome, f.FuncUltimoNome
    FROM oper_cha.Corretor co
    JOIN oper_cha.Funcionario f ON f.FuncCPF = co.FuncCPF
) src
WHERE cd.cor_CPF = src.FuncCPF
  AND cd.cor_is_atual = TRUE
  AND (cd.cor_registro   <> src.CorretorRegistro
    OR cd.cor_nome       <> src.FuncPrimNome
    OR cd.cor_sobrenome  <> src.FuncUltimoNome);

INSERT INTO Corretor_DIMENSION (cor_CPF, cor_registro, cor_nome, cor_sobrenome, cor_dt_inicio, cor_dt_fim, cor_is_atual)
SELECT
    co.FuncCPF, co.CorretorRegistro, f.FuncPrimNome, f.FuncUltimoNome,
    CURRENT_TIMESTAMP, NULL, TRUE
FROM oper_cha.Corretor co
JOIN oper_cha.Funcionario f ON f.FuncCPF = co.FuncCPF
WHERE NOT EXISTS (
    SELECT 1 FROM Corretor_DIMENSION cd
    WHERE cd.cor_CPF = co.FuncCPF AND cd.cor_is_atual = TRUE
);

-- 3) Cliente_DIMENSION (SCD Tipo 2) — mesma lógica, atributos: nome/sobrenome
UPDATE Cliente_DIMENSION cld
SET cl_dt_fim = CURRENT_TIMESTAMP,
    cl_is_atual = FALSE
FROM oper_cha.Cliente c
WHERE cld.cl_CPF = c.ClienteCPF
  AND cld.cl_is_atual = TRUE
  AND (cld.cl_nome      <> c.ClientePrimNome
    OR cld.cl_sobrenome <> c.CliUltimoNome);

INSERT INTO Cliente_DIMENSION (cl_CPF, cl_nome, cl_sobrenome, cl_dt_inicio, cl_dt_fim, cl_is_atual)
SELECT
    c.ClienteCPF, c.ClientePrimNome, c.CliUltimoNome,
    CURRENT_TIMESTAMP, NULL, TRUE
FROM oper_cha.Cliente c
WHERE NOT EXISTS (
    SELECT 1 FROM Cliente_DIMENSION cld
    WHERE cld.cl_CPF = c.ClienteCPF AND cld.cl_is_atual = TRUE
);

-- 4) Imovel_DIMENSION (SCD Tipo 2) — mesma lógica, atributos: endereço/anuncios
UPDATE Imovel_DIMENSION idim
SET im_dt_fim = CURRENT_TIMESTAMP,
    im_is_atual = FALSE
FROM (
    SELECT
        i.ImovelID,
        cep.NmLogradouro,
        e.EndBairro,
        cep.CEPMunicipio,
        uf.UFEstadoNome,
        COALESCE(anu.num_anuncios, 0) AS num_anuncios,
        COALESCE(anu.gasto_total, 0)  AS gasto_total
    FROM oper_cha.Imovel i
    JOIN oper_cha.Endereco e ON e.EndID = i.EndID
    JOIN oper_cha.CEP cep    ON cep.CEP = e.CEP
    JOIN oper_cha.UF uf      ON uf.UF = cep.UF
    LEFT JOIN (
        SELECT ImovelID, COUNT(*) AS num_anuncios, SUM(AnuncioPreco) AS gasto_total
        FROM oper_cha.Anuncio
        GROUP BY ImovelID
    ) anu ON anu.ImovelID = i.ImovelID
) src
WHERE idim.im_ID = src.ImovelID
  AND idim.im_is_atual = TRUE
  AND (idim.im_logradouro       <> src.NmLogradouro
    OR idim.im_bairro           <> src.EndBairro
    OR idim.im_cidade           <> src.CEPMunicipio
    OR idim.im_estado           <> src.UFEstadoNome
    OR idim.im_num_anuncios     <> src.num_anuncios
    OR idim.im_gasto_em_anuncios <> src.gasto_total);

INSERT INTO Imovel_DIMENSION (im_ID, im_logradouro, im_bairro, im_cidade, im_estado,
                               im_num_anuncios, im_gasto_em_anuncios,
                               im_dt_inicio, im_dt_fim, im_is_atual)
SELECT
    i.ImovelID,
    cep.NmLogradouro,
    e.EndBairro,
    cep.CEPMunicipio,
    uf.UFEstadoNome,
    COALESCE(anu.num_anuncios, 0),
    COALESCE(anu.gasto_total, 0),
    CURRENT_TIMESTAMP, NULL, TRUE
FROM oper_cha.Imovel i
JOIN oper_cha.Endereco e ON e.EndID = i.EndID
JOIN oper_cha.CEP cep    ON cep.CEP = e.CEP
JOIN oper_cha.UF uf      ON uf.UF = cep.UF
LEFT JOIN (
    SELECT ImovelID, COUNT(*) AS num_anuncios, SUM(AnuncioPreco) AS gasto_total
    FROM oper_cha.Anuncio
    GROUP BY ImovelID
) anu ON anu.ImovelID = i.ImovelID
WHERE NOT EXISTS (
    SELECT 1 FROM Imovel_DIMENSION idim
    WHERE idim.im_ID = i.ImovelID AND idim.im_is_atual = TRUE
);

-- 5) Trans_Venda_FACT — insere só transações que ainda não estão na fato
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
    ON cor.cor_CPF = tv.FuncCPF AND cor.cor_is_atual = TRUE
JOIN oper_cha.ImovelTransacao it
    ON it.TransVendaID = tv.TransVendaID
JOIN Imovel_DIMENSION im
    ON im.im_ID = it.ImovelID AND im.im_is_atual = TRUE
JOIN Data_DIMENSION dt
    ON dt.dt_data_completa = tv.TransVendaData
WHERE NOT EXISTS (
    SELECT 1 FROM Trans_Venda_FACT fv WHERE fv.tv_ID = tv.TransVendaID
);

-- 6) Vendedor_PONTE — insere só pares (tv_SK, cl_SK) novos
INSERT INTO Vendedor_PONTE (tv_SK, cl_SK)
SELECT fv.tv_SK, cl.cl_SK
FROM oper_cha.ClienteVende cv
JOIN Trans_Venda_FACT fv ON fv.tv_ID = cv.TransVendaID
JOIN Cliente_DIMENSION cl ON cl.cl_CPF = cv.ClienteCPF AND cl.cl_is_atual = TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM Vendedor_PONTE vp
    WHERE vp.tv_SK = fv.tv_SK AND vp.cl_SK = cl.cl_SK
);

-- 7) Comprador_PONTE — insere só pares (tv_SK, cl_SK) novos
INSERT INTO Comprador_PONTE (tv_SK, cl_SK)
SELECT fv.tv_SK, cl.cl_SK
FROM oper_cha.ClienteCompra cc
JOIN Trans_Venda_FACT fv ON fv.tv_ID = cc.TransVendaID
JOIN Cliente_DIMENSION cl ON cl.cl_CPF = cc.ClienteCPF AND cl.cl_is_atual = TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM Comprador_PONTE cp
    WHERE cp.tv_SK = fv.tv_SK AND cp.cl_SK = cl.cl_SK
);

-- 8) Receita_Agregada_FACT
-- Grão: 1 linha por (imóvel, dia) 
TRUNCATE TABLE Receita_Agregada_FACT;

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