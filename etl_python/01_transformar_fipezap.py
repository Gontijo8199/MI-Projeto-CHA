"""
Fase II - Camada BRONZE -> SILVER do data lake.
Lê a planilha FipeZAP (uma aba por cidade) e gera um CSV longo:
  cidade, cidade_norm, mes, dormitorios, preco_m2, var_mensal, var_12m
Apenas "Imóveis residenciais - Venda".
Uso: python etl_python/01_transformar_fipezap.py <xlsx_bronze> <csv_silver>
"""
import csv, datetime, sys, unicodedata
import openpyxl

ABAS_IGNORADAS = {"Resumo", "Aux", "Índice FipeZAP"}   # 'Índice FipeZAP' = agregado Brasil
DORM = ["Total", "1D", "2D", "3D", "4D"]
# colunas (0-based) do bloco "Imóveis residenciais / Venda" nas abas de cidade
COL_VAR_MENSAL, COL_VAR_12M, COL_PRECO = 7, 12, 17

def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return s.upper().strip()

def num(v):
    return float(v) if isinstance(v, (int, float)) else None   # '.' = sem dado

def main(src, dst):
    wb = openpyxl.load_workbook(src, read_only=True, data_only=True)
    n = 0
    with open(dst, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["cidade", "cidade_norm", "mes", "dormitorios", "preco_m2", "var_mensal", "var_12m"])
        for aba in wb.sheetnames:
            if aba in ABAS_IGNORADAS:
                continue
            for r in wb[aba].iter_rows(values_only=True):
                if not isinstance(r[1], datetime.datetime):
                    continue
                for k, d in enumerate(DORM):
                    preco = num(r[COL_PRECO + k])
                    if preco is None:
                        continue
                    w.writerow([aba, norm(aba), r[1].date().isoformat(), d, round(preco, 2),
                                num(r[COL_VAR_MENSAL + k]), num(r[COL_VAR_12M + k])])
                    n += 1
    print(f"{n} linhas -> {dst}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
